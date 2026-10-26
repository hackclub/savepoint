# The repository's commits during Save Point, for the reviewer: from the project's hours start (D-065) to the moment of the ship.
# GitHub's API needs no token for a public repository. GithubAuth (a GitHub App, or a token) lifts the rate limit.
# Never raises: a failure is a result with a plain message.
class Ship::Commits
  API = "https://api.github.com"
  LIMIT = 100
  REPO = %r{\Ahttps?://(?:www\.)?github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?(?:[/?#].*)?\z}i

  Commit = Data.define(:sha, :message, :author, :date, :url)
  # status: :ok, :not_github, :not_found, :rate_limited, :error. more: the repository has more than LIMIT.
  Result = Data.define(:status, :commits, :message, :more) do
    def ok? = status == :ok
  end

  def self.repo_path(url) = url.to_s.match(REPO)&.then { "#{it[1]}/#{it[2]}" }

  def self.headers
    { "Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2022-11-28" }.merge(GithubAuth.headers)
  end

  def self.for(ship) = new(ship.repo_url, since: ship.project.hours_start, until_time: ship.created_at || Time.current).fetch

  def initialize(repo_url, since:, until_time:)
    @repo = self.class.repo_path(repo_url)
    @since = since
    @until = until_time
  end

  def fetch
    return failure(:not_github, "This repository isn't on GitHub, so its commits can't be listed. Open it by hand.") unless @repo

    query = { since: @since.utc.iso8601, until: @until.utc.iso8601, per_page: LIMIT }.to_query
    response = Web.get("#{API}/repos/#{@repo}/commits?#{query}", headers: headers)
    return success(response) if response.ok?

    case response.status
    when 404 then failure(:not_found, "GitHub can't find #{@repo}. It may be private or the link may be wrong.")
    when 409 then Result.new(status: :ok, commits: [], message: nil, more: false)
    when 403, 429 then failure(:rate_limited, rate_message(response))
    else failure(:error, "GitHub answered with an error (#{response.status}). Try again in a minute.")
    end
  rescue Web::Error, JSON::ParserError
    failure(:error, "GitHub couldn't be reached. Try again in a minute.")
  end

  private
    def success(response)
      list = response.json.map do |item|
        Commit.new(sha: item["sha"].to_s.first(7), message: item.dig("commit", "message").to_s.lines.first.to_s.strip,
                   author: item.dig("commit", "author", "name") || item.dig("author", "login"),
                   date: Time.zone.parse(item.dig("commit", "author", "date").to_s), url: item["html_url"])
      end
      Result.new(status: :ok, commits: list, message: nil, more: list.size >= LIMIT)
    end

    def rate_message(response)
      reset = response.headers["x-ratelimit-reset"].to_i
      when_text = reset.positive? ? " It resets at #{Time.zone.at(reset).utc.strftime("%H:%M")} UTC." : ""
      "GitHub's rate limit is used up.#{when_text}"
    end

    def failure(status, message) = Result.new(status:, commits: [], message:, more: false)

    def headers = self.class.headers
end
