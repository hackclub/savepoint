# One time someone shipped their project: the title, description, links and screenshot they submitted (kept as they
# were, whatever happens to the project after) and the hours it took. An admin reviews it (Admin::ShipsController), then
# a second look checks it for fraud, as on playground (D-063):
#
#   in_review (awaiting review) -> awaiting_fraud -> approved
#                               -> changes_needed (they fix it and ship again)
#                               -> rejected (final; a fraud ban ends here too)
#
# Only a fraud check that passes makes a ship approved, with hours to spend (Project#hours_approved) and a row in
# Airtable. Until then the participant sees "in review". Nobody is messaged by any of this (D-034).
class Ship < ApplicationRecord
  include AirtableSynced

  # The columns the Airtable copy (AirtableFields.ship) reads. A change to the status or the approved hours also
  # marks the project, whose approved hours come from its ships.
  AIRTABLE_COLUMNS = %w[status title description repo_url demo_url hours approved_hours hackatime_projects claimed_hours
                        technical_features deflation_reason review_judgement].freeze
  after_update -> { Project.where(id: project_id).update_all(synced_at: nil, updated_at: Time.current) }, if: -> { saved_change_to_status? || saved_change_to_approved_hours? }
  # D-098: the participant gets a DM once the fraud check passes (Nudge::Approved).
  after_update_commit -> { Nudge::Approved.queue(self) }, if: -> { saved_change_to_status?(to: "approved") }
  STATUSES = %w[in_review awaiting_fraud approved changes_needed rejected].freeze
  # The verdicts of a review (decide!): approved moves the ship to its fraud check, banned is fraud found at review.
  DECISIONS = %w[approved changes_needed rejected banned].freeze
  # The verdicts of a fraud check (Admin::ShipsController#fraud): pass, pass with a deduction, or ban.
  FRAUD_VERDICTS = %w[pass deduct ban].freeze
  # Where a ship stands, for the admin tabs: the stored status, in the words an admin reads.
  STAGES = { "in_review" => "awaiting review", "awaiting_fraud" => "awaiting fraud check", "approved" => "approved",
             "changes_needed" => "changes needed", "rejected" => "rejected" }.freeze
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

  # The checkbox under the screenshot: it shows the game running inside the tool, not a mockup.
  attribute :screenshot_shows_game, :boolean, default: false

  normalizes :title, :description, :changes_made, with: ->(value) { value.strip }
  normalizes :repo_url, :demo_url, with: ->(url) { Ship.with_scheme(url) }

  validates :status, inclusion: { in: STATUSES }
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
  # Each project's newest ship (of those in the scope so far): the one that stands, whatever came before it.
  scope :latest_per_project, -> { where(id: select("MAX(id)").group(:project_id)) }

  def in_review? = status == "in_review"
  def awaiting_fraud? = status == "awaiting_fraud"
  def pending? = in_review? || awaiting_fraud?
  def approved? = status == "approved"
  def changes_needed? = status == "changes_needed"
  def rejected? = status == "rejected"

  # An admin can't review or fraud-check their own ship.
  def by?(user) = project.user_id == user.id

  # The hours that count under D-003: Hackatime time on the game from the project's hours_start (D-065) to the ship, never
  # more than the ship logged. The sync has clipped time before that start (D-055), so the days from the first streak
  # day hold only counted time. The jame gam's own cutoff isn't applied yet (it needs access to its database), and a
  # reviewer sees any earlier Unified YSWS DB record beside this.
  def counted_hours
    return 0 unless project&.user

    project.user.hours_in(Program::FIRST_STREAK_DATE..(created_at || Time.current).to_date).to_d.clamp(0, hours)
  end

  # D-063: the seconds on each linked Hackatime project from the hours start (D-065) to now, kept as hackatime_seconds when the
  # ship is made, so the review can set them beside the live figures. Left unset when Hackatime can't say.
  def capture_hackatime_seconds
    user = project&.user
    return unless user&.hackatime_linked? && hackatime_projects.any?

    self.hackatime_seconds = Hackatime.project_seconds(user, hackatime_projects, project.hours_start..Time.current)
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    nil
  end

  # The most the handbook allows for the hours that count (D-030): AI coding at a third, art at most 30%.
  def limits(claimed = counted_hours) = Ship::Limits.new(claimed:, ai_coding_seconds:, art_seconds:, lapse_seconds:, lapse_coding_hours:)

  # D-085: the hours of the Lapse time the reviewer calls coding, from the review page. Held between 0 and the Lapse hours
  # Hackatime counted. False, with an error on the ship, when it isn't a number in that range or the ship isn't in review.
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

  # D-050: the checklist ticks the app already knows, each with its reason: { "continued" => [ true, "..." ] }. A key it cannot
  # decide is left out (never runs, readme or hours_fit). `earlier` is this ship's Ship::EarlierShip result.
  # screenshot_shows_game is not stored: the create validation refuses a ship without it, so an attached screenshot was attested.
  def checklist_defaults(earlier:, limits: self.limits(counted_hours))
    defaults = {}
    defaults["continued"] = [ true, "Earlier ship found in the Unified YSWS DB." ] if earlier.found?
    defaults["screenshot"] = [ true, "They attested at ship time that it shows the game running." ] if screenshot.attached?
    if limits.art_known?
      defaults["art_cap"] = if limits.art_cut < Ship::Limits::TOLERANCE
        [ true, "Hackatime's art time is within the #{Ship::Limits::ART_CAP_PERCENT}% cap." ]
      else
        [ false, "Hackatime's art time is over the cap. The limits already cut it; confirm the deflation holds." ]
      end
    end
    if earlier.checked?
      defaults["not_double"] = if earlier.overlapping_entry(after: project.hours_start.utc.to_date)
        [ false, "The Unified YSWS DB has an approval after this project's hours began counting." ]
      else
        [ true, "No approval after this project's hours began counting in the Unified YSWS DB." ]
      end
    end
    defaults
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

    window = { from: project.hours_start, to: created_at.utc }
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
  def decide!(decision, by:, coding_hours: nil, art_hours: nil, technical_features: nil, deflation_reason: nil, feedback: nil,
                judgement: nil, evidence: nil, checklist_defaults: {})
    return false unless in_review? && DECISIONS.include?(decision)

    errors.clear
    self.review_feedback = feedback.to_s.strip.presence
    self.review_judgement = judgement.to_s.strip.presence
    # D-050: the app's ticks freeze with the decision, under any the reviewer saved. Stored only when it decides.
    frozen = checklist_defaults.transform_values(&:first).merge(review_checklist)
    case decision
    when "approved" then approve_review(by, coding_hours, art_hours, technical_features, deflation_reason, frozen)
    when "changes_needed"
      errors.add(:review_feedback, "Tell the participant what to change") if review_feedback.nil?
      close_review("changes_needed", by, frozen)
    when "rejected"
      errors.add(:review_judgement, "Say what is missing: a reject is final") if review_judgement.nil?
      close_review("rejected", by, frozen)
    when "banned" then ban_for_fraud!(by:, notes: evidence, checklist: frozen)
    end
  end

  # The fraud check passes, or passes with a deduction (hours taken off the review's, which need notes). The ship is
  # then approved: its hours are the participant's to spend, and it goes to Airtable. False when it isn't awaiting the check.
  def pass_fraud!(by:, deduction: 0, notes: nil)
    return false unless awaiting_fraud?

    errors.clear
    deduction = deduction.to_d.clamp(0, review_hours.to_d).floor(2)
    self.fraud_notes = notes.to_s.strip.presence
    errors.add(:fraud_notes, "Say why you deduct hours") if deduction.positive? && fraud_notes.nil?
    return false if errors.any?

    update!(status: "approved", fraud_status: deduction.positive? ? "deducted" : "passed", fraud_reviewer: by,
            fraud_reviewed_at: Time.current, fraud_deduction_hours: deduction, approved_hours: review_hours - deduction,
            decided_by: by, decided_at: Time.current)
    true
  end

  # Fraud found, at review or at the fraud check: the ship is rejected for good and the account banned (User#ban!).
  # Needs the evidence.
  def ban_for_fraud!(by:, notes:, checklist: nil)
    return false unless pending?

    errors.clear
    self.fraud_notes = notes.to_s.strip.presence
    errors.add(:fraud_notes, "Write what shows the fraud") if fraud_notes.nil?
    return false if errors.any?

    transaction do
      assign_attributes(reviewer: by, reviewed_at: Time.current, review_checklist: checklist || review_checklist) if in_review?
      update!(status: "rejected", fraud_status: "banned", fraud_reviewer: by, fraud_reviewed_at: Time.current, approved_hours: nil,
              review_feedback: review_feedback.presence || "This project was rejected.", decided_by: by, decided_at: Time.current)
      project.user.ban!(fraud_notes, by:)
    end
    true
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
      send_backs.create!(user: by, reason:, earlier_review: earlier_review)
      update!(status: "in_review", fraud_status: nil, reviewer: nil, reviewed_at: nil, review_coding_hours: nil, review_art_hours: nil,
              review_hours: nil, review_judgement: nil, review_feedback: nil, technical_features: nil, deflation_reason: nil,
              claimed_hours: nil, review_checklist: {})
    end
    true
  end

  # What a review held, for the send-back that clears it.
  def earlier_review
    { reviewer: reviewer&.first_name, reviewed_at:, coding_hours: review_coding_hours&.to_f, art_hours: review_art_hours&.to_f,
      hours: review_hours&.to_f, technical_features:, judgement: review_judgement, deflation_reason:, feedback: review_feedback }
  end

  private
    def approve_review(by, coding_hours, art_hours, technical_features, deflation_reason, frozen)
      claimed = counted_hours
      limits = limits(claimed)
      coding, art, below = limits.approve(coding_hours.presence&.to_d, art_hours.presence&.to_d)
      self.technical_features = technical_features.to_s.strip.presence
      reason = deflation_reason.to_s.strip.presence
      errors.add(:technical_features, "Name the specific technical features that explain the hours") if self.technical_features.nil?
      errors.add(:deflation_reason, "Say why you approve fewer hours than the rules allow") if below && reason.nil?
      return false if errors.any?

      total = coding + art
      # Only when the hours went down: the limits' own words for an AI or art cut, then the reviewer's, so the Airtable
      # justification has both. A reason given when nothing was cut isn't kept.
      cut = ([ limits.reason, reason ].compact.join(" ").presence if claimed - total >= Ship::Limits::TOLERANCE)
      update!(status: "awaiting_fraud", fraud_status: "pending", reviewer: by, reviewed_at: Time.current, claimed_hours: claimed,
              review_coding_hours: coding, review_art_hours: art, review_hours: total, deflation_reason: cut,
              approved_hours: nil, decided_by: nil, decided_at: nil, review_checklist: frozen)
      true
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
