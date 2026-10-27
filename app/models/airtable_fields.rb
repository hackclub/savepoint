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

  # The Unified YSWS DB couldn't be asked about a ship's code URL, so its duplicate justification can't be written.
  # The row fails to build and waits its hour (Airtable::SyncJob), rather than going without one.
  class UnifiedUnchecked < StandardError; end

  # An approved ship, in the YSWS template's field names. The screenshot goes only when the row is made, so a
  # reviewer's edits in Airtable stay. The phone number is never sent. `earlier` is the ship's Ship::EarlierShip
  # result, when the caller has it already.
  def ship(s, earlier: nil)
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
      "Optional - Override Hours Spent" => new_hours(s),
      **justifications(s, earlier: earlier || unified(s))
    }.compact_blank
  end

  # The handbook's separate justification fields (D-030). "Optional - Override Hours Spent Justification" stays empty:
  # a small YSWS that writes to Airtable fills these instead. The admin ship page shows the same.
  def justifications(s, earlier:)
    {
      "Justification - Hackatime Project Name(s) + Date Range(s)" => hackatime_projects(s),
      "Justification - Submitter Hackatime ID" => s.project.user.hackatime_uid,
      "Justification - Specific Technical Features" => s.technical_features,
      "Justification - Deflation Justification" => deflation(s),
      "Justification - Additional Justification" => additional(s),
      "Justification - Alternate Tracking Method" => alternate_tracking(s),
      "Optional - Override Duplicate Justification" => duplicate(s, earlier)
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

  def new_hours(s) = [ (cumulative_hours(s) - earlier_hours(s)).round(2), 0 ].max

  # Where this ship's hours start: the project's hours start (D-065), or for an update the day of the last earlier approved ship.
  def hours_from(s) = earlier_ships(s).last&.created_at&.utc&.to_date || s.project.hours_start.utc.to_date

  # "7/20/2026", the handbook's date format.
  def us_date(date) = date.strftime("%-m/%-d/%Y")

  def date_range(s) = "#{us_date(hours_from(s))}-#{us_date(s.created_at.utc.to_date)}"

  # "rhythm-game 10/23/2026-10/27/2026, beat-sheet-art 10/23/2026-10/27/2026": each project with the one range
  # its time counts in.
  def hackatime_projects(s)
    names = Array(s.hackatime_projects).compact_blank
    names.map { "#{it} #{date_range(s)}" }.join(", ").presence
  end

  def hours_text(hours) = "#{Ship::Limits.format(hours)} #{hours.to_d == 1 ? "hour" : "hours"}"

  # The hours deflated to and why: the numbers from the ship, the reason as the reviewer wrote it. Only for a ship
  # decided with its counted hours kept (claimed_hours) and approved below them. A deduction at the fraud check is part
  # of it, with the fraud notes (D-063).
  def deflation(s)
    return unless s.claimed_hours && s.approved_hours && s.claimed_hours - s.approved_hours >= Ship::Limits::TOLERANCE

    deducted = ("The fraud check deducted #{hours_text(s.fraud_deduction_hours)}: #{s.fraud_notes}" if s.fraud_deduction_hours.positive?)
    "Deflated from #{hours_text(s.claimed_hours)} to #{hours_text(s.approved_hours)}, Hackatime time since " \
      "#{us_date(s.project.hours_start.utc.to_date)}. #{[ s.deflation_reason, deducted ].compact_blank.join(" ")}".strip
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

  def additional(s)
    parts = []
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
  def duplicate(s, earlier)
    parts = []
    others = earlier&.found? ? earlier.entries : []
    start = s.project.hours_start.utc.to_date
    if others.any?
      parts << "This code URL is already in the Unified YSWS DB: #{others.map { record_text(it) }.join("; ")}."
      parts << "Save Point counts only Hackatime time from #{us_date(start)}, when this project's hours began counting, so time those records counted before then is not claimed again."
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
      parts << "This record claims only the #{hours_text(new_hours(s))} since then, #{date_range(s)}."
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
