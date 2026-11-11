# One time someone shipped their project: the title, description, links and screenshot they submitted (kept as they
# were, whatever happens to the project after) and the hours it took. An admin reviews it (Admin::ShipsController), then
# a second look checks it for fraud, as on playground (D-063):
#
#   in_review (awaiting review) -> awaiting_fraud -> approved
#                               -> changes_needed (they fix it and ship again)
#                               -> rejected (final; a fraud ban ends here too)
#                               -> superseded (D-109: the participant shipped again before its first review; the newer
#                                  ship is reviewed instead, and this one is out of every queue and count)
#
# Only a fraud check that passes makes a ship approved, with hours to spend (Project#hours_approved) and a row in
# Airtable. Until then the participant sees "in review". Nobody is messaged by any of this (D-034).
class Ship < ApplicationRecord
  include AirtableSynced

  # The columns the Airtable copy (AirtableFields.ship) reads. A change to the status or the approved hours also
  # marks the project, whose approved hours come from its ships.
  AIRTABLE_COLUMNS = %w[status title description repo_url demo_url hours approved_hours hackatime_projects claimed_hours
                        technical_features deflation_reason review_judgement].freeze
  # Gate audit finding 15: an edit after the Unified YSWS DB took the row cannot be sent, so it is marked for the admins.
  after_update -> { update_columns(changed_after_unified_at: Time.current) }, if: -> { in_unified? && (saved_changes.keys & AIRTABLE_COLUMNS).any? }
  belongs_to :real_name_ticked_by, class_name: "User", optional: true
  after_update -> { Project.where(id: project_id).update_all(synced_at: nil, updated_at: Time.current) }, if: -> { saved_change_to_status? || saved_change_to_approved_hours? }
  # D-098: the participant gets a DM once the fraud check passes (Nudge::Approved).
  after_update_commit -> { Nudge::Approved.queue(self) }, if: -> { saved_change_to_status?(to: "approved") }
  # D-137: the participant gets a DM when a ship is rejected for good, unless the ban that rejected it tells them instead.
  after_update_commit -> { Nudge::Rejected.queue(self) }, if: -> { saved_change_to_status?(to: "rejected") && fraud_status != "banned" }
  # D-139: the participant gets a DM when a ship gets Changes needed, with the time they have to ship again.
  after_update_commit -> { Nudge::ChangesNeeded.queue(self) }, if: -> { saved_change_to_status?(to: "changes_needed") }
  STATUSES = %w[in_review awaiting_fraud approved changes_needed rejected superseded].freeze
  # The verdicts of a review (decide!): approved moves the ship to its fraud check, banned is fraud found at review.
  DECISIONS = %w[approved changes_needed rejected banned].freeze
  # D-135: what the review form's draft holds, and the longest text it keeps for a field.
  REVIEW_DRAFT_KEYS = %w[decision coding_hours art_hours lapse_coding_hours ai_coding_hours ai_reason technical_features deflation_reason
                         feedback judgement evidence].freeze
  REVIEW_DRAFT_MAX = 10_000
  # D-150: the justification text an admin may fix on an approved ship until the Unified YSWS DB takes it.
  REVIEW_TEXT_FIELDS = %w[technical_features review_judgement deflation_reason].freeze
  IN_UNIFIED_MESSAGE = "This ship is already in the Unified YSWS DB, so its text can't change."
  # The verdicts of a fraud check (Admin::ShipsController#fraud): pass, pass with a deduction, or ban.
  FRAUD_VERDICTS = %w[pass deduct ban].freeze
  # Where a ship stands, for the admin tabs: the stored status, in the words an admin reads.
  STAGES = { "in_review" => "awaiting review", "awaiting_fraud" => "awaiting fraud check", "approved" => "approved",
             "changes_needed" => "changes needed", "rejected" => "rejected", "superseded" => "replaced" }.freeze
  # D-109: what a reviewer is told when they try to judge a ship the participant has since replaced.
  REPLACED_MESSAGE = "The participant shipped again, so this ship was replaced. Review their newer ship instead."
  # D-109: what a reviewer is told when an earlier ship of the same project is still in its fraud check.
  WAITING_ON_EARLIER_MESSAGE = "An earlier ship of this project is still in its fraud check. Judge this one after it."
  DESCRIPTION_MIN = 40
  # D-030: the Hackatime categories the handbook's limits read (Ship::Limits). Art is "designing", the category
  # Hackatime gives design and art tools, plus "timelapsing", the category Lapse gives its heartbeats (D-042;
  # hackclub/lapse sets it, so the two never overlap). Together they're one art time under one cap.
  AI_CODING_CATEGORY = "ai coding"
  LAPSE_CATEGORY = "timelapsing"
  ART_CATEGORIES = [ "designing", LAPSE_CATEGORY ].freeze
  # http or https only, with a real host: javascript:, data: and the like never pass (they would run in an admin's browser).
  URL = %r{\Ahttps?://[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?(?::\d{1,5})?(?:[/?#]\S*)?\z}i

  # The column is still demo_url (D-020 renamed it for people, not in the database).
  def self.human_attribute_name(attribute, options = {}) = attribute.to_s == "demo_url" ? "Playable link" : super

  belongs_to :project
  # D-109: the newer ship that replaced this one while it was still waiting for its first review.
  belongs_to :superseded_by, class_name: "Ship", optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  belongs_to :reviewer, class_name: "User", optional: true
  belongs_to :fraud_reviewer, class_name: "User", optional: true
  has_many :claims, dependent: :delete_all
  has_many :send_backs, -> { order(:created_at) }, class_name: "ShipSendBack", dependent: :delete_all
  has_one_attached :screenshot
  # An admin can add more (Ship::Snapshot). `screenshot` stays the cover, so everything that reads it keeps working;
  # these follow it, and Ship::Snapshot#screenshots is the whole list in order.
  has_many_attached :extra_screenshots
  belongs_to :snapshot_edited_by, class_name: "User", optional: true
  belongs_to :review_draft_updated_by, class_name: "User", optional: true

  # The checkbox under the screenshot: it shows the game running inside the tool, not a mockup.
  attribute :screenshot_shows_game, :boolean, default: false

  normalizes :title, :description, :changes_made, with: ->(value) { value.strip }
  normalizes :repo_url, :demo_url, with: ->(url) { Ship.with_scheme(url) }

  validates :status, inclusion: { in: STATUSES }
  # D-097: a later ship's approval is the earlier approval plus the new hours, so it never falls below the earlier one.
  validate :hours_hold_earlier_approval
  # D-111: every deflation has a reason. From the review on (awaiting its fraud check, approved), hours below the hours claimed need a
  # deflation reason, the approved hours are the review's less the fraud deduction, and a deduction needs its notes. A blank
  # text is no reason. The database holds the same three rules (ships_deflation_has_reason, ships_approved_hours_add_up,
  # ships_deduction_has_notes), for a write that skips these.
  validate :deflation_has_reason, if: -> { awaiting_fraud? || approved? }
  validate :approved_hours_add_up, if: :approved?
  validates :fraud_notes, presence: { message: "Say why you deduct hours" }, if: -> { fraud_deduction_hours.to_d.positive? }
  validates :title, presence: { message: "Set the title" }, length: { maximum: 80, too_long: "Make the title %{count} characters or fewer" }
  validates :description, presence: { message: "Write a description" }
  validates :description, length: { minimum: DESCRIPTION_MIN, too_short: "Make the description %{count}+ characters" }, allow_blank: true
  # Set by the ship form (ShipsController), which is the only place the statement is required: ships made any other
  # way (older ones, tests, scripts) don't carry one.
  attribute :changes_required, :boolean, default: false
  # D-002: what changed since the game's last version, for the reviewer to read beside the repository's commits.
  validates :changes_made, presence: { message: "Say what you changed since last time" }, if: :changes_required
  # A link as typed, trimmed, with https:// added when it has no scheme ("github.com/you/game").
  def self.with_scheme(url)
    stripped = url.to_s.strip
    stripped.match?(%r{\A[a-z][a-z0-9+.-]*://}i) || stripped.blank? ? stripped : "https://#{stripped}"
  end

  validates :repo_url, format: { with: URL, message: "Add a repository link" }
  validates :demo_url, format: { with: URL, message: "Add a playable link" }
  validates :screenshot, presence: { message: "Set a new screenshot" }
  # Only a new screenshot is checked, so a ship that already has one (a GIF from before they were refused) still decides.
  validate :screenshot_is_an_image, if: -> { attachment_changes["screenshot"] }
  # D-016: a ship made through the form carries a screenshot no earlier ship of the project used.
  validate :screenshot_is_new, if: :changes_required
  # D-019, D-020: the public README has to contain the playable link. Only a README certainly without it blocks.
  validate :readme_links_demo, if: :changes_required
  validates :screenshot_shows_game, acceptance: { message: "Confirm the screenshot shows your game", accept: true },
                                    on: :create

  # in_review is awaiting a review. pending is that or awaiting its fraud check: not decided, as the participant sees it.
  scope :in_review, -> { where(status: "in_review") }
  scope :awaiting_fraud, -> { where(status: "awaiting_fraud") }
  scope :pending, -> { where(status: %w[in_review awaiting_fraud]) }
  scope :approved, -> { where(status: "approved") }
  scope :decided, -> { where(status: %w[approved changes_needed rejected]) }
  scope :superseded, -> { where(status: "superseded") }
  # D-109: ships a reviewer can pick up: in review, with no earlier ship of the project still in its fraud check. A ship that
  # passed review but not yet its fraud check isn't an approval (D-097), so judging the later ship waits for it: then the
  # later ship's new hours start from the right approval, and no hour counts twice.
  scope :reviewable, -> {
    in_review.where.not("EXISTS (SELECT 1 FROM ships earlier WHERE earlier.project_id = ships.project_id AND earlier.id < ships.id " \
                        "AND earlier.status = 'awaiting_fraud')")
  }
  # Each project's newest ship (of those in the scope so far): the one that stands, whatever came before it.
  scope :latest_per_project, -> { where(id: select("MAX(id)").group(:project_id)) }

  def in_review? = status == "in_review"
  def awaiting_fraud? = status == "awaiting_fraud"
  def pending? = in_review? || awaiting_fraud?
  def approved? = status == "approved"
  def changes_needed? = status == "changes_needed"
  def rejected? = status == "rejected"
  def superseded? = status == "superseded"

  # D-109: an earlier ship of the project that is in its fraud check, when there is one. Its verdict comes first.
  def waiting_on_earlier
    return unless project && persisted?

    project.ships.awaiting_fraud.where(id: ...id).order(:id).first
  end

  # D-109: the participant shipped again while this ship waited for its first review. It leaves the review queue and every
  # count, stays on the project for the record, and keeps a link to the ship that replaced it. Any claim on it goes. False
  # when it is no longer in review (a reviewer got there first: then it stays, and the newer ship waits on its fraud check).
  def supersede!(by:)
    with_lock do
      next false unless in_review?

      update_columns(status: "superseded", superseded_by_id: by.id, updated_at: Time.current)
      claims.delete_all
      true
    end
  end

  # An admin can't review or fraud-check their own ship.
  def by?(user) = project.user_id == user.id

  # The hours that count under D-003: Hackatime time on the game from the project's hours_start (D-065) to the ship, never
  # more than the ship logged. The sync has clipped time before that start (D-055), so the days from the first streak
  # day hold only counted time. The jame gam's own cutoff isn't applied yet (it needs access to its database), and a
  # reviewer sees any earlier Unified YSWS DB record beside this.
  def counted_hours
    return 0 unless project&.user

    last_day = [ (created_at || Time.current).to_date, project.hours_last_day ].compact.min
    project.user.hours_in(Program::FIRST_STREAK_DATE..last_day).to_d.clamp(0, hours)
  end

  # D-155: where this ship's Hackatime time stops: now, or the public end for a project with a private ship window (ship_until).
  def hours_end
    project.ship_until && Time.current > Program::ENDS_AT ? Program::ENDS_AT : Time.current
  end

  # D-063: the seconds on each linked Hackatime project from the hours start (D-065) to now, kept as hackatime_seconds when the
  # ship is made, so the review can set them beside the live figures. Left unset when Hackatime can't say.
  def capture_hackatime_seconds
    user = project&.user
    return unless user&.hackatime_linked? && hackatime_projects.any?

    self.hackatime_seconds = Hackatime.project_seconds(user, hackatime_projects, project.hours_start..hours_end)
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    nil
  end

  # D-097: the approval a later ship builds on: the latest approved ship of the project made before this one. `hours` is its
  # cumulative approved total, `coding` and `art` that total split as the review stored it (all coding when none was stored,
  # and a fraud deduction comes off coding first), and `on` the date of that ship. nil for a first ship.
  EarlierApproval = Data.define(:ship, :hours, :coding, :art, :on)

  def earlier_approval
    return unless project && created_at

    prior = project.ships.approved.where.not(id: id)
                   .where("ships.created_at < :at OR (ships.created_at = :at AND ships.id < :id)", at: created_at, id: id || 0)
                   .order(:created_at, :id).last
    return unless prior

    hours = (prior.approved_hours || prior.hours).to_d
    art = [ prior.review_art_hours.to_d, hours ].min
    EarlierApproval.new(ship: prior, hours:, coding: hours - art, art:, on: prior.created_at.to_date)
  end

  # D-101: the new hours of a later ship, for the review queue's "Update" label: the hours the ship would add, or added, to the
  # earlier approval. nil for a first ship, and for a ship that was turned down (it has no total).
  def update_hours
    prior = earlier_approval
    total = if approved? then approved_hours
    elsif awaiting_fraud? then review_hours
    elsif in_review? then counted_hours
    end
    [ total.to_d - prior.hours, 0 ].max if prior && total
  end

  # The most the handbook allows for the hours that count (D-030): AI coding at a third, art at most 30%.
  def limits(claimed = counted_hours)
    Ship::Limits.new(claimed:, ai_coding_seconds:, art_seconds:, lapse_seconds:, lapse_coding_hours:, reviewer_ai_hours: reviewer_ai_in_force)
  end

  # D-102, D-097: the AI coding hours the reviewer set that the limits use. On a later ship the figure is the project's, so the
  # earlier approval's figure holds when this ship has none or less. nil when neither ship has one.
  def reviewer_ai_in_force
    [ reviewer_ai_coding_hours, earlier_approval&.ship&.reviewer_ai_in_force ].compact.max
  end

  # D-102: the reviewer's AI coding hours for a ship in review, with why. Never below Hackatime's figure (0 if it is unknown) or
  # the earlier approval's, and never above the coding hours claimed. A figure above the one in force needs a reason. A blank
  # value, or one at the lowest allowed, clears it. False, with errors on the ship, when it can't be set.
  def set_reviewer_ai!(value, reason)
    errors.clear
    text = value.to_s.strip
    why = reason.to_s.strip
    hackatime = (ai_coding_seconds.to_i.to_d / 3600)
    held = earlier_approval&.ship&.reviewer_ai_in_force
    low = [ hackatime, held.to_d ].max
    baseline = Ship::Limits.new(claimed: counted_hours, ai_coding_seconds:, art_seconds:, lapse_seconds:, lapse_coding_hours:)
    top = baseline.coding.floor(2)
    hours = (BigDecimal(text) if text.match?(/\A\d+(\.\d+)?\z/))
    if !in_review?
      errors.add(:reviewer_ai_coding_hours, "Only a ship in review takes this")
    elsif text.present? && hours.nil?
      errors.add(:reviewer_ai_coding_hours, "Enter the AI coding hours, like 3.5")
    elsif hours && hours < low.floor(2)
      errors.add(:reviewer_ai_coding_hours, held && held > hackatime ? "The earlier approval already counted #{Ship::Limits.hrs(held)} of AI coding, so it can't be less" : "Hackatime has #{Ship::Limits.hrs(hackatime)} of AI coding, so it can't be less")
    elsif hours && hours > top
      errors.add(:reviewer_ai_coding_hours, "Only #{Ship::Limits.hrs(top)} of coding was claimed, so AI coding can't be more")
    elsif hours && hours - low >= Ship::Limits::TOLERANCE && why.empty?
      errors.add(:reviewer_ai_reason, "Say what looked AI-generated")
    end
    return false if errors.any?

    if hours.nil? || hours - low < Ship::Limits::TOLERANCE
      update!(reviewer_ai_coding_hours: nil, reviewer_ai_reason: nil)
    else
      update!(reviewer_ai_coding_hours: hours.round(2), reviewer_ai_reason: why)
    end
    true
  end

  # D-085: the hours of the Lapse time the reviewer calls coding, from the review page. Held between 0 and the Lapse hours
  # Hackatime counted. False, with an error on the ship, when it isn't a number in that range or the ship isn't in review.
  # D-135: merges these fields into the review draft, for a ship in review, and returns the merged draft (nil when the ship is not in
  # review). Only the keys in REVIEW_DRAFT_KEYS are kept, a nil is skipped and "" clears a field. It never decides the ship, never
  # changes the hours the limits read and never tells the participant.
  # `loaded_at` is the review_draft_updated_at the writer's page was filled from (a Time, or nil for a page that loaded no draft).
  # When the stored draft is newer, nothing is written and the answer is :stale: the page holds older text than the server.
  # Leave `loaded_at` out (the MCP tools) to write without the check.
  def save_review_draft!(fields, by:, loaded_at: :unchecked)
    return unless in_review?

    fields = fields.to_h.stringify_keys.slice(*REVIEW_DRAFT_KEYS).compact.transform_values { it.to_s[0, REVIEW_DRAFT_MAX] }
    fields.delete("decision") unless fields["decision"].nil? || fields["decision"].in?(DECISIONS + [ "" ])
    with_lock do
      stored_at = review_draft_updated_at
      return :stale if loaded_at != :unchecked && stored_at && (loaded_at.nil? || stored_at > loaded_at)

      merged = review_draft.to_h.merge(fields)
      update_columns(review_draft: merged, review_draft_updated_at: Time.current, review_draft_updated_by_id: by.id) if fields.any?
      merged
    end
  end

  # D-135: the draft the review form fills from. Empty once the ship is out of review, and while the form shows errors, so what was
  # typed before the error wins.
  def form_draft = in_review? && errors.none? ? review_draft.to_h : {}

  def set_lapse_coding!(value)
    errors.clear
    hours = (BigDecimal(value.to_s.strip) if value.to_s.strip.match?(/\A\d+(\.\d+)?\z/))
    top = limits.lapse.floor(2)
    if !in_review?
      errors.add(:lapse_coding_hours, "Only a ship in review takes this")
    elsif hours.nil?
      errors.add(:lapse_coding_hours, "Enter the Lapse hours that were coding, like 2.5")
    elsif hours > top
      errors.add(:lapse_coding_hours, "Lapse time is #{Ship::Limits.hrs(top)}, so coding can't be more")
    end
    return false if errors.any?

    update!(lapse_coding_hours: hours.round(2))
    true
  end

  # D-050: the checklist ticks the app already knows, each with its reason: { "screenshot" => [ true, "..." ] }. A key it cannot
  # decide is left out (never runs, readme or hours_fit). `earlier` is this ship's Ship::EarlierShip result.
  # screenshot_shows_game is not stored: the create validation refuses a ship without it, so an attached screenshot was attested.
  def checklist_defaults(earlier:, limits: self.limits(counted_hours))
    defaults = {}
    defaults["screenshot"] = [ true, "They attested at ship time that it shows the game running." ] if screenshot.attached?
    if limits.art_known?
      defaults["art_cap"] = if limits.art_cut < Ship::Limits::TOLERANCE
        [ true, "Hackatime's art time is within the #{Ship::Limits::ART_CAP_PERCENT}% cap." ]
      else
        [ false, "Hackatime's art time is over the cap. The limits already cut it; confirm the deflation holds." ]
      end
    end
    if earlier.checked?
      defaults["not_double"] = if earlier.overlapping_entry(user: project.user, from: project.hours_start.utc.to_date, to: (created_at || Time.current).utc.to_date)
        [ false, "The Unified YSWS DB has an earlier record of this person covering time after this project's hours began counting." ]
      else
        [ true, "No earlier record of this person in the Unified YSWS DB covers time after this project's hours began counting." ]
      end
    end
    defaults["real_name"] = [ false, RealName.new(self).concern || "Nothing in the name looks wrong, but the app never ticks this. Read it and tick it." ]
    defaults
  end

  CHECKLIST_KEYS = %w[runs readme screenshot hours_fit art_cap not_double real_name].freeze

  # D-143: the Real name item, ticked by a reviewer or an agent, never by the app. Gates the Unified YSWS box.
  # Gate audit finding 5: the tick counts only while the names now on the user equal the names it was ticked for.
  def real_name_checked?
    names = AirtableFields.names(project.user)
    review_checklist["real_name"] == true && names.all?(&:present?) && [ real_name_first, real_name_last ] == names
  end

  # The tick was made, but for other names than the ones the user has now (they signed in again and Hack Club Auth sent new ones).
  def real_name_stale?
    review_checklist["real_name"] == true && real_name_first.present? && [ real_name_first, real_name_last ] != AirtableFields.names(project.user)
  end

  # Gate audit findings 2, 5, 14 and the zero-hours case: why the Unified YSWS box stays unticked, in plain words. Empty when
  # nothing holds it. Eligibility (D-147) is asked separately, because it can call Hack Club Auth.
  def unified_holds
    user = project.user
    holds = []
    holds << "The owner is banned." if user.banned?
    if real_name_stale?
      holds << "The Real name tick was for #{real_name_first} #{real_name_last}, and the name is now #{AirtableFields.names(user).join(" ")}. A reviewer ticks it again."
    elsif !real_name_checked?
      holds << "Real name is not ticked."
    end
    holds << "No new hours since the earlier ship." if AirtableFields.earlier_ships(self).any? && AirtableFields.new_hours(self).zero?
    missing = missing_unified_fields
    holds << "The record is incomplete: #{missing.to_sentence} missing." if missing.any?
    holds
  end

  # The Unified YSWS DB has this ship: it took the row (in_unified), or the Airtable row's "Automation - Status" reads
  # "2–Submitted" (the sync copies it into unified_status).
  def sent_to_unified? = in_unified? || unified_status.to_s.start_with?("2")

  # Where an approved ship stands on its way to the Unified YSWS DB, from stored data only (the sync keeps it, no Airtable call).
  # Returns [key, label, detail]: key is sent, held, error, processing or not_synced; detail is the full text for a hover.
  def unified_state
    return [ "sent", "Sent to Unified", nil ] if sent_to_unified?

    holds = unified_holds
    return [ "held", "Held: #{holds.first.delete_suffix(".")}", holds.join(" ") ] if holds.any?
    return [ "error", "Error: #{unified_error.squish.truncate(60)}", unified_error ] if unified_error.present?
    return [ "error", "Error: sync to Airtable failed", "The sync to Airtable failed and tries again within the hour." ] if airtable_failed_at && synced_at.nil?
    return [ "processing", "Processing", unified_status.presence ] if synced_at

    [ "not_synced", "Not synced yet", nil ]
  end

  # The fields the Unified YSWS row needs that are empty, by the row's own names.
  def missing_unified_fields
    user = project.user
    address = ShippingAddress.for(user)
    first, last = AirtableFields.names(user)
    { "First Name" => first, "Last Name" => last, "Email" => user.email, "Address (Line 1)" => address.street_address,
      "City" => address.locality, "Country" => address.country, "Birthday" => user.birthdate, "Code URL" => repo_url,
      "Playable URL" => demo_url }.select { |_, value| value.blank? }.keys
  end

  # D-147: the Unified YSWS box needs the Real name tick and a YSWS eligible person. A person stored as not eligible is asked
  # about again (Hack Club Auth may have verified them since); one stored as eligible is not asked at every sync.
  def submit_to_unified?
    user = project.user
    unified_holds.empty? && (user.ysws_eligible? || user.confirm_ysws_eligibility!)
  end

  # D-143: Real name is the one tick that can still change after the verdict, because ships approved before it exists wait for it.
  def review_text_open? = approved? && !in_unified?

  # D-150: fixes the justification text of an approved ship the Unified YSWS DB has not taken. Only the three text fields change,
  # never hours, verdicts or links. The ship is marked unsynced (AirtableSynced) so the corrected text goes out with its first send.
  # Returns the changes ({ field => [old, new] }, empty when nothing differs), or false with the reason in errors.
  def fix_review_text!(fields, by:)
    typed = fields.to_h.stringify_keys.slice(*REVIEW_TEXT_FIELDS).transform_values { it.to_s.strip.presence }
    with_lock do
      next errors.add(:base, "Only an approved ship takes a text fix.") && false unless approved?
      next errors.add(:base, IN_UNIFIED_MESSAGE) && false if in_unified?

      changes = typed.reject { |name, value| self[name] == value }.to_h { |name, value| [ name, [ self[name], value ] ] }
      errors.add(:technical_features, "Say which technical features explain the hours") if changes.key?("technical_features") && typed["technical_features"].nil?
      if changes.key?("deflation_reason") && typed["deflation_reason"].nil? && claimed_hours && review_hours && review_hours < claimed_hours
        errors.add(:deflation_reason, "Say why the hours went down from the #{Ship::Limits.hrs(claimed_hours)} claimed")
      end
      next false if errors.any?
      next changes if changes.empty?

      transaction do
        update!(changes.transform_values(&:last))
        AdminAuditEvent.create!(user: by, tool: "edit_review_text", ids: { "ship_id" => id, "changes" => changes })
      end
      changes
    end
  end

  def checklist_open_for?(key) = in_review? || (approved? && key.to_s == "real_name")

  # Saves a tick. Ticking Real name on an approved ship sends its row again, with the Unified YSWS box set from the new value.
  # `by` is the reviewer. A Real name tick keeps the names it was made for, who ticked and when.
  # D-152: Real name can't be ticked while a name is missing or an initial. Returns false then, with the reason in errors[:base].
  def tick_checklist!(key, value, by: nil)
    key = key.to_s
    if key == "real_name" && value == true && (problem = full_name_problem)
      errors.add(:base, "Real name can't be ticked yet. #{problem}")
      return false
    end
    attrs = { review_checklist: review_checklist.merge(key => value == true) }
    if key == "real_name"
      ticked = value == true
      first, last = ticked ? AirtableFields.names(project.user) : [ nil, nil ]
      attrs.merge!(real_name_first: first, real_name_last: last, real_name_ticked_by: (by if ticked), real_name_ticked_at: (Time.current if ticked))
    end
    update!(attrs)
    update_columns(synced_at: nil, airtable_failed_at: nil) if approved? && key == "real_name" && !in_unified?
    true
  end

  # D-152: why the person has no full name for the Unified YSWS DB: a first or last name that is missing, or only an initial
  # ("D", "D."). Nil when both are whole names. Whether the name is a real person's stays the reviewer's call (D-143).
  def full_name_problem
    first, last = AirtableFields.names(project.user)
    { "first" => first, "last" => last }.each do |which, name|
      return "Their #{which} name is missing, so they need to sign in to Hack Club Auth again." if name.blank?
      return "Their #{which} name is an initial (#{name}), so they need to enter their full name in Hack Club Auth and sign in again." if name.gsub(/[^\p{L}]/, "").length < 2
    end
    nil
  end

  # D-050: a tick as the reviewer sees it. Their saved tick wins, either way. Otherwise the app's default, otherwise unticked.
  def checklist_tick(key, defaults)
    review_checklist.key?(key) ? review_checklist[key] : (defaults[key]&.first || false)
  end

  # Everything a reviewer sees beside the ship (Admin::ShipsController, AdminMcp): its project's other ships, the repository's
  # commits, the earlier ship in the Unified YSWS DB, and the limits on its hours. Looked up each time, never stored (D-002).
  Review = Data.define(:others, :commits, :earlier_ship, :limits)

  def review
    Review.new(others: project.ships.where.not(id: id).order(created_at: :desc), commits: Ship::Commits.for(self),
               earlier_ship: Ship::EarlierShip.for(self), limits: limits(in_review? ? counted_hours : (claimed_hours || hours)))
  end

  # Asks Hackatime for the ship's "ai coding" and art time from the project's hours start (D-065) to the ship, once, while it's in
  # review, and keeps it. If Hackatime can't say, both stay unknown and the review page says so.
  def fetch_hackatime_categories!
    return unless in_review? && (ai_coding_seconds.nil? || art_seconds.nil? || lapse_seconds.nil?)

    user = project&.user
    return unless user&.hackatime_linked?

    window = { from: project.hours_start, to: [ created_at.utc, hours_end ].min }
    ai = Hackatime.category_seconds(user, hackatime_projects, AI_CODING_CATEGORY, **window)
    art_parts = ART_CATEGORIES.map { |category| Hackatime.category_seconds(user, hackatime_projects, category, **window) }
    art = art_parts.sum unless art_parts.any?(&:nil?) # one unknown part leaves the art time unknown
    lapse = art_parts[ART_CATEGORIES.index(LAPSE_CATEGORY)] # D-085: kept apart, for the reviewer's split
    update_columns(ai_coding_seconds: ai, art_seconds: art, lapse_seconds: (lapse if art))
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    nil
  end

  # A review's verdict, made once: false if the ship isn't awaiting review (or the verdict isn't one), or if a box it
  # needs is empty, with errors on the ship (D-063, as playground's approve_review!, return_for_changes!, reject_review!
  # and ban_for_fraud!).
  #
  # - approved: coding_hours and art_hours (nil asks for the most the limits allow) are held to the handbook's limits
  #   (limits.approve, D-030): AI coding at a third, art at most 30% of the total. It needs the specific technical
  #   features, and a reason when the reviewer goes below what the rules allow. The ship then waits for its fraud check
  #   (pass_fraud!): the hours are not the participant's to spend yet.
  # - changes_needed: needs the note to the participant (D-049). They fix it and ship again, hours kept.
  # - rejected: final. Needs the reviewer's judgement.
  # - banned: fraud found at review. Needs the evidence, and bans the account.
  #
  # D-148: an approval also passes the gates (#approval_blockers). `overrides` holds the reasons that lift the ones a reason can lift,
  # by key ("limits", "double", "duplicate"). Whoever decides, web page or job, goes through here.
  def decide!(decision, by:, coding_hours: nil, art_hours: nil, technical_features: nil, deflation_reason: nil, feedback: nil,
                judgement: nil, evidence: nil, checklist_defaults: {}, overrides: {})
    return false unless DECISIONS.include?(decision)

    # D-109: under the row's lock, so a verdict can't land on a ship the participant replaces at the same moment.
    transaction do
      stored = Ship.lock.where(id:).pick(:status)
      if superseded? || stored == "superseded"
        errors.add(:base, REPLACED_MESSAGE)
        next false
      end
      next false unless in_review? && stored == "in_review"

      errors.clear
      if waiting_on_earlier
        errors.add(:base, WAITING_ON_EARLIER_MESSAGE)
        next false
      end
      decided = decide_in_review(decision, by:, coding_hours:, art_hours:, technical_features:, deflation_reason:, feedback:, judgement:,
                                 evidence:, checklist_defaults:, overrides: overrides.to_h.stringify_keys)
      # D-135: the verdict used the draft up. A ship sent back to review starts from the earlier review, not a stale draft.
      update_columns(review_draft: {}, review_draft_updated_at: nil, review_draft_updated_by_id: nil) if decided
      decided
    end
  end

  def decide_in_review(decision, by:, coding_hours:, art_hours:, technical_features:, deflation_reason:, feedback:, judgement:,
                       evidence:, checklist_defaults:, overrides:)
    self.review_feedback = feedback.to_s.strip.presence
    self.review_judgement = judgement.to_s.strip.presence
    # D-050: the app's ticks freeze with the decision, under any the reviewer saved. Stored only when it decides.
    frozen = checklist_defaults.transform_values(&:first).merge(review_checklist)
    case decision
    when "approved" then approve_review(by, coding_hours, art_hours, technical_features, deflation_reason, frozen, overrides)
    when "changes_needed"
      errors.add(:review_feedback, "Tell the participant what to change") if review_feedback.nil?
      close_review("changes_needed", by, frozen)
    when "rejected"
      errors.add(:review_judgement, "Say what is missing: a reject is final") if review_judgement.nil?
      close_review("rejected", by, frozen)
    when "banned" then ban_for_fraud!(by:, notes: evidence, checklist: frozen)
    end
  end
  private :decide_in_review

  # D-148: a gate on approving. override is true when a typed reason lifts it, false when nothing does.
  Blocker = Data.define(:key, :message, :override)
  OVERRIDE_KEYS = %w[limits double duplicate].freeze

  # D-148: what stands in the way of approving this ship, whoever presses it (web page, job). `frozen` is the checklist as the verdict
  # would store it (the app's ticks under the reviewer's). The checklist itself still never blocks (D-049); only these do:
  # a red Hackatime trust level (D-148), limits Hackatime couldn't say (D-030),
  # an overlap with another program (D-110), and a second account on the same repo or person (D-148).
  def approval_blockers(frozen:, evidence: Ship::Evidence.new(self), limits: self.limits(counted_hours))
    list = []
    # D-152: a full first and last name with Real name ticked, for the Unified YSWS DB. No reason lifts it.
    if (problem = full_name_problem)
      list << Blocker.new("name", "Approve needs a full first and last name with Real name ticked. #{problem}", false)
    elsif !real_name_checked?
      list << Blocker.new("real_name", "Tick Real name first.", false)
    end
    list << Blocker.new("trust", "Hackatime's trust level for this person is red, so they can't be approved.", false) if evidence.trust_level == "red"
    list << Blocker.new("limits", "Hackatime did not say how much was AI coding or art, so no cut applies.", true) unless limits.known?
    list << Blocker.new("double", "The Unified YSWS DB has an earlier record of this person covering time after this project's hours began counting.", true) if frozen["not_double"] == false
    if (duplicate = evidence.duplicates.first)
      list << Blocker.new("duplicate", "Another account has the same #{duplicate.reason.sub("same ", "")}.", true)
    end
    list
  end

  # The fraud check passes, or passes with a deduction (hours taken off the review's, which need notes). The ship is
  # then approved: its hours are the participant's to spend, and it goes to Airtable. False when it isn't awaiting the check.
  def pass_fraud!(by:, deduction: 0, notes: nil)
    return false unless awaiting_fraud?

    # D-148: under the row's lock, so a pass and a send-back landing together can't both win, and never for a banned owner.
    transaction do
      next false unless Ship.lock.where(id:).pick(:status) == "awaiting_fraud"

      errors.clear
      if project.user.banned?
        errors.add(:base, "This account is banned.")
        next false
      end
      # D-097: a deduction comes off the new hours only; the earlier approval stands.
      held = earlier_approval&.hours.to_d
      deduction = deduction.to_d.clamp(0, [ review_hours.to_d - held, 0 ].max).floor(2)
      self.fraud_notes = notes.to_s.strip.presence
      errors.add(:fraud_notes, "Say why you deduct hours") if deduction.positive? && fraud_notes.nil?
      errors.add(:base, "Hackatime's trust level for this person is red, so they can't be approved.") if project.user.hackatime_banned?
      next false if errors.any?

      update!(status: "approved", fraud_status: deduction.positive? ? "deducted" : "passed", fraud_reviewer: by,
              fraud_reviewed_at: Time.current, fraud_deduction_hours: deduction, approved_hours: review_hours - deduction,
              decided_by: by, decided_at: Time.current)
      true
    end
  end

  # What a banned participant's rejected ship says when the reviewer wrote nothing of their own under Ban (D-112).
  BAN_NOTE = "This project was rejected.".freeze

  # Fraud found, at review or at the fraud check: the ship is rejected for good and the account banned (User#ban!).
  # Needs the evidence. The message to the participant is the reviewer's own words under Ban (D-112); a ship at the fraud
  # check holds the one written under Approve, which isn't the ban's, so it gets BAN_NOTE.
  def ban_for_fraud!(by:, notes:, checklist: nil)
    return false unless pending?

    errors.clear
    self.fraud_notes = notes.to_s.strip.presence
    errors.add(:fraud_notes, "Write what shows the fraud") if fraud_notes.nil?
    return false if errors.any?

    from_review = in_review?
    transaction do
      # D-148: under the row's lock, so a ban can't land on a ship another admin has decided in the meantime.
      next false unless Ship.lock.where(id:).pick(:status).in?(%w[in_review awaiting_fraud])

      assign_attributes(reviewer: by, reviewed_at: Time.current, review_checklist: checklist || review_checklist) if from_review
      update!(status: "rejected", fraud_status: "banned", fraud_reviewer: by, fraud_reviewed_at: Time.current, approved_hours: nil,
              review_feedback: (review_feedback.presence if from_review) || BAN_NOTE, decided_by: by, decided_at: Time.current)
      project.user.ban!(fraud_notes, by:)
      true
    end
  end

  # A ship waiting for its fraud check goes back to review, with a reason. The review is cleared (kept in the send-back,
  # which refills the form) and the ship keeps its place in the queue, so it is next. Nobody is told.
  def send_back_to_review!(by:, reason:)
    return false unless awaiting_fraud?

    errors.clear
    reason = reason.to_s.strip
    errors.add(:base, "Say why it goes back to review") if reason.empty?
    return false if errors.any?

    transaction do
      next false unless Ship.lock.where(id:).pick(:status) == "awaiting_fraud"

      send_backs.create!(user: by, reason:, earlier_review: earlier_review)
      update!(status: "in_review", fraud_status: nil, reviewer: nil, reviewed_at: nil, review_coding_hours: nil, review_art_hours: nil,
              review_hours: nil, review_judgement: nil, review_feedback: nil, technical_features: nil, deflation_reason: nil,
              claimed_hours: nil, review_checklist: {})
      true
    end
  end

  # What a review held, for the send-back that clears it.
  def earlier_review
    { reviewer: reviewer&.first_name, reviewed_at:, coding_hours: review_coding_hours&.to_f, art_hours: review_art_hours&.to_f,
      hours: review_hours&.to_f, technical_features:, judgement: review_judgement, deflation_reason:, feedback: review_feedback }
  end

  private
    def hours_hold_earlier_approval
      return unless (approved? && will_save_change_to_approved_hours?) || (awaiting_fraud? && will_save_change_to_review_hours?)

      total = approved? ? approved_hours : review_hours
      held = earlier_approval&.hours
      return if total.nil? || held.nil? || total.to_d >= held

      errors.add(:approved_hours, "Approved hours can't be below the #{Ship::Limits.hrs(held)} already approved")
    end

    def deflation_has_reason
      return unless claimed_hours && review_hours && review_hours < claimed_hours && deflation_reason.blank?

      errors.add(:deflation_reason, "Say why the hours went down from the #{Ship::Limits.hrs(claimed_hours)} claimed")
    end

    def approved_hours_add_up
      return if approved_hours && review_hours && approved_hours == review_hours - fraud_deduction_hours

      errors.add(:approved_hours, "Approved hours are the review's hours less the fraud deduction")
    end

    def approve_review(by, coding_hours, art_hours, technical_features, deflation_reason, frozen, overrides = {})
      # D-111: the limits read the counted hours to the hundredth, as claimed_hours stores them, so approving the most the rules
      # allow stores exactly the most (Ship::Limits#coding_top).
      limits = limits(counted_hours)
      claimed = limits.claimed
      # D-097: on a later ship the figures typed are the new hours. The limits are read on the whole project, and the
      # earlier approval's coding and art are added back, so the ship keeps cumulative totals.
      earlier = earlier_approval
      if earlier
        coding, art, below = limits.approve_new(earlier.coding, earlier.art, coding_hours.presence&.to_d, art_hours.presence&.to_d)
        coding += earlier.coding
        art += earlier.art
      else
        coding, art, below = limits.approve(coding_hours.presence&.to_d, art_hours.presence&.to_d)
      end
      self.technical_features = technical_features.to_s.strip.presence
      reason = deflation_reason.to_s.strip.presence
      errors.add(:technical_features, "Name the specific technical features that explain the hours") if self.technical_features.nil?
      errors.add(:deflation_reason, "Say why you approve fewer hours than the rules allow") if below && reason.nil?
      total = coding + art
      # D-148: a reason for going below the rules has to name the cut, in hours, so a stray word can't stand for it.
      if below && reason && !reason_names_the_cut?(reason, limits.most - total, total)
        errors.add(:deflation_reason, "Say how many hours you cut in the reason: #{Ship::Limits.hrs([ limits.most - total, 0 ].max)}, or the #{Ship::Limits.hrs(total)} you approve")
      end
      used = lift_blockers(by, overrides, frozen, limits)
      # Only when the hours went down, by a hundredth too (D-111): the limits' own words for an AI or art cut, then the reviewer's,
      # so the Airtable justification has both. A reason given when nothing was cut isn't kept. Hours that went down with no
      # words to say why can't be approved.
      cut = ([ limits.reason, reason ].compact.join(" ").presence if claimed > total)
      errors.add(:deflation_reason, "Say why you approve fewer than the #{Ship::Limits.hrs(claimed)} claimed") if claimed > total && cut.nil? && errors[:deflation_reason].empty?
      return false if errors.any?

      update!(status: "awaiting_fraud", fraud_status: "pending", reviewer: by, reviewed_at: Time.current, claimed_hours: claimed,
              review_coding_hours: coding, review_art_hours: art, review_hours: total, deflation_reason: cut,
              approved_hours: nil, decided_by: nil, decided_at: nil, review_checklist: frozen, review_overrides: used)
      true
    end

    # D-148: the blockers a typed reason lifts become errors when it is missing. Returns the reasons that were used, to keep.
    def lift_blockers(by, overrides, frozen, limits)
      approval_blockers(frozen:, limits:).each_with_object({}) do |blocker, used|
        reason = overrides[blocker.key].to_s.strip
        if !blocker.override
          errors.add(:base, blocker.message)
        elsif reason.empty?
          errors.add(:base, "#{blocker.message} Type a reason to approve anyway.")
        elsif blocker.key == "limits" && !reason.match?(/\d/)
          errors.add(:base, "#{blocker.message} Type the AI coding and art hours you checked, with your reason.")
        else
          used[blocker.key] = { "reason" => reason, "by" => by.id, "at" => Time.current.iso8601 }
        end
      end
    end

    # D-148: a figure in the reason matches the hours cut (or the hours approved) to about a hundredth.
    def reason_names_the_cut?(reason, cut, total)
      reason.scan(/\d+(?:\.\d+)?/).map(&:to_d).any? { |figure| [ cut, total ].any? { (figure - it).abs <= BigDecimal("0.015") } }
    end

    def close_review(status, by, frozen)
      return false if errors.any?

      update!(status:, reviewer: by, reviewed_at: Time.current, decided_by: by, decided_at: Time.current, approved_hours: nil, review_checklist: frozen)
      true
    end

    def readme_links_demo
      return if errors[:repo_url].any? || errors[:demo_url].any?
      return unless Ship::Checklist.new(repo_url:, demo_url:).readme_without_demo?

      errors.add(:demo_url, "Put your playable link in the README")
    end

    def screenshot_is_new
      return unless screenshot.attached? && project

      earlier = project.ships.where.not(id: id).includes(screenshot_attachment: :blob)
      return unless earlier.any? { it.screenshot.attached? && it.screenshot.blob.checksum == screenshot.blob.checksum }

      errors.add(:screenshot, "Set a new screenshot: this one was on an earlier ship")
    end

    def screenshot_is_an_image
      return unless screenshot.attached?

      if !Project::SCREENSHOT_TYPES.include?(screenshot.blob.content_type)
        errors.add(:screenshot, "Set a still screenshot as a PNG, JPEG or WebP, not a GIF")
      elsif screenshot.blob.byte_size > Project::SCREENSHOT_MAX_SIZE
        errors.add(:screenshot, "Set a new screenshot under 5 MB")
      end
    end
end
