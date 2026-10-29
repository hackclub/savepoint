# The field hash each Postgres row becomes in Airtable. Names are in AirtableSchema.
# Only what review and fulfilment need: no phone, no tokens, no Slack data beyond
# the id. A shipping address and birthday go only on the submission row, as the
# YSWS template asks (playground sends them there too).
module AirtableFields
  module_function

  def user(u)
    {
      AirtableSchema::ID_FIELD => "user-#{u.id}",
      "Email" => u.email,
      "Name" => u.name,
      "First Name" => u.first_name,
      "Slack ID" => u.slack_id,
      "Hack Club Auth ID" => u.hca_id,
      "Hackatime ID" => u.hackatime_uid,
      "Verification Status" => u.verification_status,
      "YSWS Eligible" => u.ysws_eligible,
      "Signed Up At" => u.created_at&.iso8601
    }.compact
  end

  def project(p)
    {
      AirtableSchema::ID_FIELD => "project-#{p.id}",
      "Name" => p.title,
      "Idea" => p.idea,
      "User ID" => "user-#{p.user_id}",
      "Repo URL" => p.repo_url.presence,
      "Prize" => p.prize_key,
      "Goal Hours" => p.chosen_prize&.hours,
      "Hours Approved" => p.hours_approved.round(2),
      "Hours Spent" => p.hours_spent.round(2),
      "Pace Minutes" => p.pace_minutes,
      "Build Time" => p.build_time,
      "Signed On" => p.signed_on&.iso8601,
      "Jame Gam" => p.jame_gam,
      "Hackatime Projects" => Array(p.hackatime_projects).join(", ").presence,
      "Created At" => p.created_at&.iso8601
    }.compact
  end

  # No address and no recipient name: an admin posts the order from the app.
  def order(o)
    {
      AirtableSchema::ID_FIELD => "order-#{o.id}",
      "Project ID" => "project-#{o.project_id}",
      "Prize" => o.prize_key,
      "Prize Name" => o.prize_item&.name,
      "Hours" => o.hours&.to_f,
      "Status" => o.status,
      "Ordered At" => o.ordered_at&.iso8601,
      "Created At" => o.created_at&.iso8601
    }.compact
  end

  # The deflation field of the submission row, and how every sentence the app writes into it begins.
  DEFLATION_FIELD = "Justification - Deflation Justification"
  DEFLATION_START = "Deflated from "

  # The Unified YSWS DB couldn't be asked about a ship's code URL, so its duplicate justification can't be written.
  # The row fails to build and waits its hour (Airtable::SyncJob), rather than going without one.
  class UnifiedUnchecked < StandardError; end

  # D-111: a ship approved below its claimed hours with a part of the cut that has no words. Every deflation has a reason, so the
  # row doesn't build and waits its hour too, until the reason is there. The message names the part.
  class UnexplainedDeflation < StandardError; end

  # An approved ship, in the YSWS template's field names. The screenshot goes only when the row is made, so a
  # reviewer's edits in Airtable stay. The phone number is never sent. `earlier` is the ship's Ship::EarlierShip
  # result, when the caller has it already.
  def ship(s, earlier: nil)
    earlier ||= unified(s)
    window = claim_window(s, earlier)
    user = s.project.user
    address = ShippingAddress.for(user).attributes
    first = user.first_name.to_s
    {
      AirtableSchema::ID_FIELD => "ship-#{s.id}",
      "Code URL" => s.repo_url,
      "Playable URL" => s.demo_url,
      "First Name" => first.presence,
      "Last Name" => user.name.to_s.delete_prefix(first).strip.presence,
      "Email" => user.email,
      "Screenshot" => (screenshot(s) if s.airtable_record_id.blank?),
      "Description" => s.description,
      "GitHub Username" => s.repo_url.to_s[%r{\Ahttps://github\.com/([\w-]+)/}, 1],
      "Address (Line 1)" => address["street_address"],
      "Address (Line 2)" => address["street_address_2"],
      "City" => address["locality"],
      "State / Province" => address["region"],
      "Country" => address["country"],
      "ZIP / Postal Code" => address["postal_code"],
      "Birthday" => user.birthdate.presence,
      "Optional - Override Hours Spent" => new_hours(s, window),
      **justifications(s, earlier:, window:)
    }.compact_blank
  end

  # The handbook's separate justification fields (D-030). "Optional - Override Hours Spent Justification" stays empty:
  # a small YSWS that writes to Airtable fills these instead. The admin ship page shows the same, and asks for strict: false
  # so a deflation with no reason (D-111) leaves its field out and shows a warning (deflation_problem), where the sync raises.
  def justifications(s, earlier:, window: claim_window(s, earlier), strict: true)
    {
      "Justification - Hackatime Project Name(s) + Date Range(s)" => hackatime_projects(s, window),
      "Justification - Submitter Hackatime ID" => s.project.user.hackatime_uid,
      "Justification - Specific Technical Features" => s.technical_features,
      DEFLATION_FIELD => deflation(s, window, strict:),
      "Justification - Additional Justification" => additional(s, window),
      "Justification - Alternate Tracking Method" => alternate_tracking(s),
      "Optional - Override Duplicate Justification" => duplicate(s, earlier, window)
    }.compact_blank
  end

  def unified(s)
    result = Ship::EarlierShip.for(s)
    raise UnifiedUnchecked, result.status.to_s unless result.checked?

    result
  end

  # A ship's approved hours count everything since the program started (Ship#counted_hours), so the Unified YSWS DB
  # gets only the hours since the project's last earlier approved ship.
  def cumulative_hours(s) = (s.approved_hours || s.hours).to_f

  def earlier_ships(s)
    s.project.ships.approved.where.not(id: s.id)
     .where("ships.created_at < :at OR (ships.created_at = :at AND ships.id < :id)", at: s.created_at, id: s.id)
     .order(:created_at, :id)
  end

  def earlier_hours(s) = earlier_ships(s).map { cumulative_hours(it) }.max.to_f

  # D-110: the hours of the claim window before the participant's own hours start are added to the participant's counted hours.
  def new_hours(s, window = nil) = [ (cumulative_hours(s) - earlier_hours(s) + (window || NO_WINDOW).hours).round(2), 0 ].max

  # D-110: where the Unified YSWS DB record's time starts, and the hours between that start and the project's hours_start
  # (the participant's own start, D-065). Only the Unified record sees them: the project page, prize hours and review limits
  # still count from hours_start. `start` is nil when the window is the project's own (a later ship, or Hackatime can't say).
  # `end_label` names where the gap ends ("sign-up"), `source` what set its start (:launch, :jame_gam or :unified). `hours` is
  # the gap after the ship's deflation share, `raw_hours` what Hackatime has in it (D-111: the deflation text runs from it).
  ClaimWindow = Data.define(:start, :hours, :raw_hours, :source, :claim_program)
  NO_WINDOW = ClaimWindow.new(start: nil, hours: 0, raw_hours: 0, source: nil, claim_program: nil)

  # Unified start = the later of Program::STARTS_AT and the end of the latest known other-program claim on this game: the jame gam
  # submission's created time (Project#jame_gam_submitted_at, D-066), or a Unified YSWS DB record of the same code URL. A
  # record gives an approval time: "Approved At" is a plain date in that base, so a date is taken as the end of that day, UTC
  # (it can only err late, which claims less). A reviewer's start later than that still wins. Only a project's first Unified record
  # has a window: a later Save Point ship starts after the earlier approved one (hours_from). Gap hours are Hackatime's time on the
  # ship's projects between the two starts (each moment once), cut by the ship's approved/claimed ratio so the AI and art
  # deflation applies proportionally, never above Hackatime. If Hackatime can't answer, there is no gap: today's start, logged.
  def claim_window(s, earlier)
    project = s.project
    return NO_WINDOW if earlier_ships(s).any?

    claims = []
    claims << [ project.jame_gam_submitted_at, :jame_gam, nil ] if project.jame_gam_submitted_at
    (earlier&.found? ? earlier.entries : []).each do |entry|
      at = claim_end(entry.approved_at)
      claims << [ at, :unified, entry.program ] if at
    end
    latest = claims.max_by(&:first)
    start, source, program = Program::STARTS_AT, :launch, nil
    start, source, program = latest if latest && latest.first > start
    start = [ start, project.hours_start_override ].compact.max if project.hours_start_override
    return NO_WINDOW unless start < project.hours_start

    seconds = Hackatime.seconds_between(project.user, Array(s.hackatime_projects).compact_blank, start..project.hours_start)
    ratio = s.claimed_hours&.positive? && s.approved_hours ? [ s.approved_hours / s.claimed_hours, 1 ].min : 1
    hours = (seconds / 3600.0 * ratio.to_f).floor(2)
    hours.positive? ? ClaimWindow.new(start:, hours:, raw_hours: (seconds / 3600.0).floor(2), source:, claim_program: program) : NO_WINDOW
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable => e
    Rails.logger.warn("airtable sync: ship #{s.id} gap hours not read, #{e.class}, claiming from the project's hours start")
    NO_WINDOW
  end

  def claim_end(value)
    return if value.blank?

    text = value.to_s
    return Time.zone.parse(text).utc if text.length > 10

    (Date.parse(text.first(10)) + 1).in_time_zone("UTC") - 1.second
  rescue Date::Error, ArgumentError
    nil
  end

  # Where this ship's hours start: the Unified start (claim_window), or for an update the day of the last earlier approved ship.
  def hours_from(s, window = nil)
    earlier_ships(s).last&.created_at&.utc&.to_date || (window || NO_WINDOW).start&.utc&.to_date || s.project.hours_start.utc.to_date
  end

  # "7/20/2026", the handbook's date format.
  def us_date(date) = date.strftime("%-m/%-d/%Y")

  def date_range(s, window = nil) = "#{us_date(hours_from(s, window))}-#{us_date(s.created_at.utc.to_date)}"

  # "rhythm-game 10/23/2026-10/27/2026, beat-sheet-art 10/23/2026-10/27/2026": each project with the one range
  # its time counts in.
  def hackatime_projects(s, window = nil)
    names = Array(s.hackatime_projects).compact_blank
    names.map { "#{it} #{date_range(s, window)}" }.join(", ").presence
  end

  def hours_text(hours) = "#{Ship::Limits.format(hours)} #{hours.to_d == 1 ? "hour" : "hours"}"

  # The hours deflated to and why, each cause with its hours, worked from the same limits the review page shows
  # (Ship#limits on the hours kept, claimed_hours): AI coding counted at a third, art over the cap, the reviewer's cut below the
  # limits and the fraud check's deduction (D-063), then the reviewer's own words and the fraud notes. Only for a ship decided
  # with its counted hours kept and approved below them. D-111: every deflation has a reason, so a cut with a part that has no
  # words raises UnexplainedDeflation. The admin page and get_ship ask for strict: false and show deflation_problem instead.
  # D-110: a first ship's record also claims the gap before the participant's start, so its sentence runs from the claimed hours
  # plus the gap's hours to the record's hours (Optional - Override Hours Spent), and says the gap was cut by the same share.
  def deflation(s, window = NO_WINDOW, strict: true)
    return unless s.claimed_hours && s.approved_hours && s.claimed_hours > s.approved_hours

    parts = deflation_parts(s, s.limits(s.claimed_hours))
    raise UnexplainedDeflation, "ship #{s.id}: #{parts.missing.to_sentence}" if strict && parts.missing.any?
    return if parts.missing.any? || parts.causes.empty?

    from = s.claimed_hours + window.raw_hours.to_d
    to = window.start ? new_hours(s, window) : s.approved_hours
    since = us_date((window.start || s.project.hours_start).utc.to_date)
    gap = (" The hours before #{us_date(s.project.hours_start.utc.to_date)} are cut by the same share (#{Ship::Limits.format(window.raw_hours)} to #{hours_text(window.hours)})." if window.start && window.raw_hours > window.hours)
    typed = ("The reviewer's reason: #{parts.typed}" if parts.typed.present?)
    deducted = ("The fraud check deducted #{hours_text(s.fraud_deduction_hours)}: #{s.fraud_notes}" if s.fraud_deduction_hours.positive?)
    head = "#{DEFLATION_START}#{Ship::Limits.format(from)} to #{hours_text(to)}: #{parts.causes.join(", ")}. Hackatime time since #{since}.#{gap}"
    [ head, typed, deducted ].compact_blank.join(" ")
  end

  # D-111: a ship corrected to its claimed hours has no deflation now, but its row may still hold the sentence sent before. The
  # upsert leaves out a field with no value, so that sentence would stay beside the corrected hours. Given the fields to send
  # and the row as Airtable has it, this adds the deflation field as nil, which the upsert clears, when the row holds a sentence
  # of the app's own. Words written in Airtable stay.
  def clearing_stale_deflation(fields, record)
    old = record&.dig("fields", DEFLATION_FIELD).to_s
    return fields if fields.key?(DEFLATION_FIELD) || !old.start_with?(DEFLATION_START)

    fields.merge(DEFLATION_FIELD => nil)
  end

  # D-111: what keeps a deflation from being sent, for the admin page and get_ship to warn about: the parts of the cut that have
  # no words, in one sentence. nil when every part has its words, and when the ship is not deflated.
  def deflation_problem(s)
    return unless s.claimed_hours && s.approved_hours && s.claimed_hours > s.approved_hours

    deflation_parts(s, s.limits(s.claimed_hours)).missing.to_sentence.presence
  end

  # `causes` are the named parts, each with its hours: "1.5 hrs of AI coding counted at a third (-1 hr)", "art over the 30% cap
  # (-0.07 hrs)", "the reviewer's cut below the limits (-0.5 hrs)", "the fraud check's deduction (-1 hr)". `missing` are the
  # parts with no words, and `typed` is the reviewer's own words. The parts add up to the whole cut from the claimed hours to
  # the approved hours (D-111): what the limits cut, what the reviewer took off beyond them, and the fraud check's deduction.
  DeflationParts = Data.define(:causes, :missing, :typed)

  def deflation_parts(s, limits)
    review = s.review_hours || s.approved_hours + s.fraud_deduction_hours
    limited = [ s.claimed_hours - [ limits.most, review ].max, 0 ].max
    reviewer = [ limits.most - review, 0 ].max
    # A ship approved before D-111 can sit a hundredth under the limits' most, the round-down its floors made. When the limits
    # cut something, that hundredth is theirs, not the reviewer's.
    reviewer = 0.to_d if reviewer <= Ship::Limits::TOLERANCE && limited.positive?
    typed = reviewer_reason(s, limits)
    deduction = s.fraud_deduction_hours
    causes, missing = [], []
    if limits.ai_cut.positive?
      raised = (" (the reviewer raised Hackatime's #{Ship::Limits.hrs(limits.hackatime_ai)})" if limits.ai_raised?)
      causes << "#{Ship::Limits.hrs(limits.ai_coding)} of AI coding#{raised} counted at a third (-#{Ship::Limits.hrs(limits.ai_cut)})"
    end
    causes << "art over the #{Ship::Limits::ART_CAP_PERCENT}% cap (-#{Ship::Limits.hrs(limits.art_cut)})" if limits.art_cut.positive?
    missing << "the limits' cut of #{Ship::Limits.hrs(limited)} has no cause" if limited.positive? && causes.empty?
    if reviewer.positive?
      causes << "the reviewer's cut below the limits (-#{Ship::Limits.hrs(reviewer)})"
      missing << "the reviewer's cut of #{Ship::Limits.hrs(reviewer)} has no reason" if typed.blank?
    end
    if deduction.positive?
      causes << "the fraud check's deduction (-#{Ship::Limits.hrs(deduction)})"
      missing << "the fraud check's deduction of #{Ship::Limits.hrs(deduction)} has no notes" if s.fraud_notes.blank?
    end
    DeflationParts.new(causes:, missing:, typed:)
  end

  # approve_review keeps the limits' own wording ahead of the reviewer's reason in deflation_reason. The named causes now say
  # that part, so only the reviewer's words are left.
  def reviewer_reason(s, limits)
    reason = s.deflation_reason.to_s
    (limits.reason ? reason.sub(limits.reason, "") : reason).strip
  end

  # D-085: Lapse hours the reviewer called coding, for an editor Hackatime can't track (GameMaker Studio, say). Those hours
  # were counted from Lapse recordings, not Hackatime, and sit outside the art cap.
  def alternate_tracking(s)
    return unless s.lapse_coding_hours.positive?

    "#{hours_text(s.lapse_coding_hours)} of Lapse recordings were coding in an editor Hackatime can't track. " \
      "The reviewer counted them as coding, not art, so they sit outside the #{Ship::Limits::ART_CAP_PERCENT}% art cap."
  end

  # D-102: the reviewer set the AI coding time above Hackatime's. Counted at a third, so it cut the hours.
  def ai_raised(s)
    return unless s.reviewer_ai_coding_hours

    "The reviewer raised the AI coding time from Hackatime's #{hours_text(s.ai_coding_seconds.to_i.to_d / 3600)} to #{hours_text(s.reviewer_ai_coding_hours)} " \
      "because the code looked AI-generated: #{s.reviewer_ai_reason}"
  end

  # D-110: one sentence when the Unified record claims time before the participant's own start.
  def gap_text(s, window)
    return unless window.start

    from = us_date(window.start.utc.to_date)
    ends = s.project.hours_start_source == :sign_up ? "sign-up on #{us_date(s.project.hours_start.utc.to_date)}" : us_date(s.project.hours_start.utc.to_date)
    case window.source
    when :jame_gam then "Hours from #{from}, when this game's jame gam submission ended, to #{ends} are claimed here because no other program claims them."
    when :unified then "Hours from #{from}, when this game's #{window.claim_program} record ended, to #{ends} are claimed here because no other program claims them."
    else "Hours from #{from}, Save Point's launch, are claimed here, including time before sign-up, because no other program claims them."
    end
  end

  def additional(s, window = nil)
    parts = []
    parts << gap_text(s, window || NO_WINDOW) if window&.start
    parts << "Hackatime's AI coding time could not be read at review, so no AI coding cut applied." if s.claimed_hours && s.ai_coding_seconds.nil? && s.reviewer_ai_in_force.nil?
    parts << ai_raised(s)
    parts << "Reviewer judgement: #{s.review_judgement}" if s.review_judgement.present?
    if (host = ENV["APP_URL"].presence)
      parts << "Review in Save Point: #{Rails.application.routes.url_helpers.admin_ship_url(s, host:)}"
    end
    parts.compact.join(" ").presence
  end

  # Filled when the code URL is already on a record: in the Unified YSWS DB from another program (a Save Point game
  # often continues a jame gam game), or an earlier approved Save Point ship of this game. It names each record and
  # says that only new hours are claimed (D-003).
  def duplicate(s, earlier, window = nil)
    parts = []
    others = earlier&.found? ? earlier.entries : []
    start = (window&.start || s.project.hours_start).utc.to_date
    if others.any?
      parts << "This code URL is already in the Unified YSWS DB: #{others.map { record_text(it) }.join("; ")}."
      parts << "Save Point counts only Hackatime time from #{us_date(start)}, when #{window&.start ? "this record's claim window began" : "this project's hours began counting"}, so time those records counted before then is not claimed again."
      later = others.select { (date = parse_date(it.approved_at)) && date > start }
      later.each do |entry|
        parts << "The #{entry.program} record was approved on #{us_date(parse_date(entry.approved_at))}, after this project's hours began counting, so its time from #{us_date(start)} may overlap this record."
      end
    end
    key = Ship::EarlierShip.normalize(s.repo_url)
    same = earlier_ships(s).select { Ship::EarlierShip.normalize(it.repo_url) == key }
    if same.any?
      parts << "This updates #{same.size == 1 ? "an earlier Save Point ship" : "#{same.size} earlier Save Point ships"} of this game " \
               "(#{same.map { "#{us_date(it.created_at.utc.to_date)}, #{hours_text(cumulative_hours(it))} since Save Point began" }.join("; ")})."
      parts << "This record claims only the #{hours_text(new_hours(s, window))} since then, #{date_range(s, window)}."
    end
    parts.join(" ").presence
  end

  def record_text(entry)
    date = parse_date(entry.approved_at)
    details = [ (date ? "approved #{us_date(date)}" : "approval date unknown"), (entry.hours.present? ? hours_text(entry.hours) : "hours unknown") ]
    "#{entry.program} (#{details.join(", ")})"
  end

  def parse_date(value)
    Date.parse(value.to_s.first(10)) if value.present?
  rescue Date::Error
    nil
  end

  # A link that expires in an hour, which Airtable fetches and copies when it makes the row. Needs APP_URL.
  def screenshot(s)
    host = ENV["APP_URL"].presence
    return unless host && s.screenshot.attached?

    blob = s.screenshot.blob
    [ { "url" => Rails.application.routes.url_helpers.rails_service_blob_url(blob.signed_id(expires_in: 1.hour), blob.filename, host:) } ]
  end
end
