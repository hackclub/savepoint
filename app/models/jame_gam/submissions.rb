# D-066: one person's rows in the jame gam's "Submission Form" table (base apprhNJsC9D4nlFRB), whatever their review status.
# Read-only, and it asks for only the fields below: the table also holds addresses, birthdays and phone numbers we never pull.
# Never raises.
#
# Env JAMEGAM_AIRTABLE_TOKEN, or credentials key airtable.jamegam_token: a read-only token (data.records:read) for that base.
class JameGam::Submissions
  API = "https://api.airtable.com/v0"
  BASE = "apprhNJsC9D4nlFRB"
  TABLE = "tblmnQSVJBu5EBoVY"
  FIELDS = %w[email slack_id code_url hackatime_names review_status jam game_title].freeze
  MAX_PAGES = 10
  CACHE_FOR = 5.minutes

  # submitted_at is the record's createdTime: the moment they pressed submit.
  Submission = Data.define(:id, :submitted_at, :code_url, :hackatime_names, :review_status, :jam, :game_title) do
    # The same game as `project`: its repo, or one of its Hackatime projects. The person already matches (the query).
    # Code URL alone misses games, so a shared Hackatime project name counts too.
    def matches?(project)
      key = Ship::EarlierShip.normalize(project.repo_url)
      return true if key.length >= 8 && Ship::EarlierShip.normalize(code_url) == key

      mine = project.hackatime_projects.map { it.strip.downcase }
      names.any? { mine.include?(it) }
    end

    def names = hackatime_names.to_s.split(",").map { it.strip.downcase }.compact_blank
  end

  # status: :ok (submissions may be empty), :not_configured, :error.
  Result = Data.define(:status, :submissions, :message) do
    def ok? = status == :ok
  end

  # Tests set the token directly, so none reads the real credentials.
  class << self
    attr_writer :token

    def token = @token || ENV["JAMEGAM_AIRTABLE_TOKEN"].presence || Rails.application.credentials.dig(:airtable, :jamegam_token).presence

    def for(user)
      return Result.new(status: :not_configured, submissions: [], message: "The jame gam base is not configured") if token.blank?

      cached = Rails.cache.read(cache_key(user))
      return cached if cached

      new(email: user.email, slack_id: user.slack_id).fetch.tap { |result| Rails.cache.write(cache_key(user), result, expires_in: CACHE_FOR) if result.ok? }
    end

    private
      def cache_key(user) = [ "jame-gam-submissions", user.id, user.email, user.slack_id ]
  end

  def initialize(email:, slack_id:)
    @email = email.to_s.strip.downcase
    @slack_id = slack_id.to_s.strip
  end

  def fetch
    return Result.new(status: :ok, submissions: [], message: nil) if @email.blank? && @slack_id.blank?

    submissions = []
    offset = nil
    MAX_PAGES.times do
      response = Web.get(url(offset), headers: { "Authorization" => "Bearer #{self.class.token}" })
      return failure(response) unless response.ok?

      body = response.json
      submissions.concat(body.fetch("records").map { submission(it) })
      offset = body["offset"].presence
      return Result.new(status: :ok, submissions:, message: nil) unless offset
    end
    Result.new(status: :error, submissions: [], message: "The jame gam base has more than #{MAX_PAGES} pages of rows for one person.")
  rescue Web::Error, JSON::ParserError, KeyError, ArgumentError
    Result.new(status: :error, submissions: [], message: "The jame gam base could not be reached.")
  end

  private
    def url(offset)
      params = FIELDS.map { [ "fields[]", it ] } + [ [ "filterByFormula", formula ], [ "pageSize", 100 ] ]
      params << [ "offset", offset ] if offset
      "#{API}/#{BASE}/#{TABLE}?#{URI.encode_www_form(params)}"
    end

    def formula
      terms = []
      terms << "LOWER({email})='#{escape(@email)}'" if @email.present?
      terms << "{slack_id}='#{escape(@slack_id)}'" if @slack_id.present?
      "OR(#{terms.join(", ")})"
    end

    def escape(value) = value.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }

    def submission(record)
      fields = record["fields"].to_h
      Submission.new(id: record.fetch("id"), submitted_at: Time.iso8601(record.fetch("createdTime")), code_url: fields["code_url"].to_s,
                     hackatime_names: Array(fields["hackatime_names"]).join(", "), review_status: Array(fields["review_status"]).first.to_s.presence,
                     jam: Array(fields["jam"]).first.to_s.presence, game_title: Array(fields["game_title"]).first.to_s.presence)
    end

    def failure(response)
      message = case response.status
      when 401, 403 then "The jame gam base refused the token. Check airtable.jamegam_token."
      when 429 then "The jame gam base rate limit is used up."
      else "The jame gam base answered with an error (#{response.status})."
      end
      Result.new(status: :error, submissions: [], message:)
    end
end
