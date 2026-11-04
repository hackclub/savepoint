# The before screenshot: the game's earlier ship in the Unified YSWS DB (Hack Club's Airtable base of approved ships),
# matched by code URL. It runs each time a reviewer opens a ship, and is never stored. Never raises.
#
# Env AIRTABLE_UNIFIED_TOKEN, or credentials key airtable.unified_token: a read-only token (data.records:read) for base app3A5kJwYqxMLOgh. The table
# and fields are those playground's D-116 reads: "Approved Projects", "Code URL" and "YSWS–Name". The screenshot field
# is "Screenshot", the name playground writes it under; unconfirmed in the Unified DB itself.
class Ship::EarlierShip
  API = "https://api.airtable.com/v0"
  BASE = "app3A5kJwYqxMLOgh"
  TABLE = "Approved Projects"
  OWN_PROGRAM = "Save Point"
  REPO_HOSTS = %w[github.com gitlab.com codeberg.org bitbucket.org].freeze

  # D-149: ranges are the dates the record's time covers ([from, to] pairs read from its Hackatime projects line, empty when none
  # can be read). email and hackatime_id say whose record it is, nil when the record does not say.
  Entry = Data.define(:program, :approved_at, :hours, :code_url, :screenshot_url, :ranges, :email, :hackatime_id) do
    def initialize(program:, approved_at:, hours:, code_url:, screenshot_url:, ranges: [], email: nil, hackatime_id: nil)
      super
    end

    # The same person: the email matches, or the Hackatime ID does. A record that names neither is not known to be theirs.
    def same_person?(user)
      (email.present? && user.email.present? && email.casecmp?(user.email)) ||
        (hackatime_id.present? && user.hackatime_uid.present? && hackatime_id.to_s == user.hackatime_uid.to_s)
    end

    # Whether the dates the record covers meet from..to: true, false, or nil when no range is readable (never guessed, D-144).
    def overlaps?(from, to)
      return if ranges.empty?

      ranges.any? { |first, last| first <= to && last >= from }
    end
  end
  # status: :found, :none, :not_configured, :error. entry is the latest record, entries every one, oldest first.
  Result = Data.define(:status, :entry, :message, :entries) do
    def initialize(status:, entry:, message:, entries: [])
      super(status:, entry:, message:, entries:)
    end

    def found? = status == :found
    # Whether the Unified YSWS DB was asked and answered (found or none).
    def checked? = status.in?(%i[found none])

    # D-149: the first record of this person whose covered dates meet from..to, or whose dates can't be read. A record of another
    # person (a teammate on the same repo) is not an overlap, and a record that ends before `from` is not one even when it was
    # approved after. The overlap warning and the checklist's not_double tick (D-050) both read this, so the rule lives once.
    def overlapping_entry(user:, from:, to:)
      entries.find { it.same_person?(user) && it.overlaps?(from, to) != false }
    end
  end

  # Tests set the token directly, so none reads the real credentials.
  class << self
    attr_writer :token

    def token = @token || ENV["AIRTABLE_UNIFIED_TOKEN"].presence || Rails.application.credentials.dig(:airtable, :unified_token).presence
  end

  def self.for(ship) = new(ship.repo_url).fetch

  # "https://www.GitHub.com/A/B.git/tree/main" and "github.com/a/b" are the same game.
  def self.normalize(url)
    value = url.to_s.strip.downcase.sub(%r{\A[a-z][a-z0-9+.-]*://}, "").sub(/\Awww\./, "").sub(/[?#].*\z/, "").sub(%r{/+\z}, "")
    host, owner, repo = value.split("/")
    value = [ host, owner, repo.to_s.delete_suffix(".git") ].compact_blank.join("/") if REPO_HOSTS.include?(host) && repo.present?
    value
  end

  def initialize(code_url)
    @key = self.class.normalize(code_url)
  end

  def fetch
    return Result.new(status: :not_configured, entry: nil, message: "Unified YSWS DB not configured") if self.class.token.blank?
    return Result.new(status: :none, entry: nil, message: "No code URL to search for.") if @key.length < 8

    escaped = @key.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
    query = { filterByFormula: "FIND('#{escaped}', LOWER({Code URL}))", pageSize: 20 }.to_query
    response = Web.get("#{API}/#{BASE}/#{ERB::Util.url_encode(TABLE)}?#{query}", headers: { "Authorization" => "Bearer #{self.class.token}" })
    return failure(response) unless response.ok?

    entries = response.json.fetch("records").filter_map { entry(it["fields"].to_h) }
    latest = entries.max_by { it.approved_at.to_s }
    return Result.new(status: :none, entry: nil, message: "No earlier ship of this game in the Unified YSWS DB.") unless latest

    Result.new(status: :found, entry: latest, message: nil, entries: entries.sort_by { it.approved_at.to_s })
  rescue Web::Error, JSON::ParserError, KeyError
    Result.new(status: :error, entry: nil, message: "The Unified YSWS DB could not be reached. Reopen this ship to try again.")
  end

  private
    def entry(fields)
      return unless self.class.normalize(fields["Code URL"]) == @key

      names = Array(fields["YSWS–Name"]).map { it.to_s.strip }.compact_blank
      return if names.any? && names.all? { it.casecmp?(OWN_PROGRAM) }

      shot = Array(fields["Screenshot"]).first
      Entry.new(program: names.join(", ").presence || "unknown program", approved_at: fields["Approved At"],
                hours: fields["Override Hours Spent"], code_url: fields["Code URL"], ranges: date_ranges(fields),
                email: Array(fields["Email"]).first.to_s.strip.presence, hackatime_id: Array(fields["Justification - Submitter Hackatime ID"]).first.to_s.strip.presence,
                screenshot_url: shot.is_a?(Hash) ? (shot.dig("thumbnails", "large", "url") || shot["url"]) : nil)
    end

    # "rhythm-game 10/23/2026-10/27/2026, art 10/22/2026-10/25/2026": every M/D/YYYY-M/D/YYYY pair in the record's Hackatime projects
    # line (the justification field, or the override hours justification's "Hackatime Projects: ..." line).
    RANGE = %r{(\d{1,2}/\d{1,2}/\d{4})\s*[-\u2013]\s*(\d{1,2}/\d{1,2}/\d{4})}

    def date_ranges(fields)
      text = [ fields["Justification - Hackatime Project Name(s) + Date Range(s)"], fields["Optional - Override Hours Spent Justification"] ].join("\n")
      text.scan(RANGE).filter_map do |first, last|
        first, last = [ first, last ].map { Date.strptime(it, "%m/%d/%Y") }
        [ first, last ] if first <= last
      rescue Date::Error
        nil
      end
    end

    def failure(response)
      message = case response.status
      when 401, 403 then "The Unified YSWS DB refused the token. Check airtable.unified_token."
      when 429 then "The Unified YSWS DB rate limit is used up. Reopen this ship in a minute."
      else "The Unified YSWS DB answered with an error (#{response.status})."
      end
      Result.new(status: :error, entry: nil, message:)
    end
end
