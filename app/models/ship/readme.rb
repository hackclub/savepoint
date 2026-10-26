# The repository's README as GitHub renders it, for the reviewer (playground shows it on its review page). Asked the way
# Ship::Commits and Ship::Checklist ask: Web, with GithubAuth's headers. The HTML is kept 10 minutes, never a failure.
# Never raises: a failure is a result with a plain message. Show it with ReadmeHelper#readme_html, which cleans it.
class Ship::Readme
  # status: :ok, :not_github, :missing, :rate_limited, :error.
  Result = Data.define(:status, :html, :message, :repo) do
    def ok? = status == :ok
  end

  TTL = 10.minutes

  def self.for(ship) = new(ship.repo_url).fetch

  def initialize(repo_url)
    @repo = Ship::Commits.repo_path(repo_url)
  end

  def fetch
    return failure(:not_github, "This repository isn't on GitHub, so its README can't be shown. Open it by hand.") unless @repo

    cached = Rails.cache.read([ "ship-readme", @repo ])
    return success(cached) if cached

    response = Web.get("#{Ship::Commits::API}/repos/#{@repo}/readme", headers: Ship::Commits.headers.merge("Accept" => "application/vnd.github.html"))
    if response.ok?
      Rails.cache.write([ "ship-readme", @repo ], response.body.to_s, expires_in: TTL)
      return success(response.body.to_s)
    end

    case response.status
    when 404 then failure(:missing, "#{@repo} has no README, or GitHub can't find the repository. It may be private.")
    when 403, 429 then failure(:rate_limited, "GitHub's rate limit is used up, so the README can't be shown. Try again in a few minutes.")
    else failure(:error, "GitHub answered with an error (#{response.status}), so the README can't be shown. Try again in a minute.")
    end
  rescue Web::Error
    failure(:error, "GitHub couldn't be reached, so the README can't be shown. Try again in a minute.")
  end

  private
    def success(html) = Result.new(status: :ok, html:, message: nil, repo: @repo)

    def failure(status, message) = Result.new(status:, html: nil, message:, repo: @repo)
end
