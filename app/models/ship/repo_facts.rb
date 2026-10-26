# What GitHub says about a ship's repository, for the reviewer (D-063): its name, commit count, last push, stars and
# latest release with the files it carries. Looked up when the page opens, and a good answer is kept ten minutes.
# Never raises: a failure is a result with a plain message.
class Ship::RepoFacts
  Asset = Data.define(:name, :size)
  Release = Data.define(:tag, :url, :published_at, :assets)
  # status: :ok, :not_github, :not_found, :rate_limited, :error. release: nil when the repository has none.
  Facts = Data.define(:status, :full_name, :commits, :pushed_at, :stars, :release, :message) do
    def ok? = status == :ok

    # The release is older than the project's hours start (D-065), or than the first commit made during it, so it can't hold this work.
    def release_predates?(first_commit_at, start = Program::STARTS_AT)
      return false unless release&.published_at

      release.published_at < start || (first_commit_at.present? && release.published_at < first_commit_at)
    end
  end

  CACHE_FOR = 10.minutes

  def self.for(ship) = new(ship.repo_url).fetch

  def initialize(repo_url)
    @repo = Ship::Commits.repo_path(repo_url)
  end

  def fetch
    return failure(:not_github, "This repository isn't on GitHub, so its facts can't be read. Open it by hand.") unless @repo

    key = [ "ship-repo-facts", @repo ]
    Rails.cache.read(key) || load.tap { |facts| Rails.cache.write(key, facts, expires_in: CACHE_FOR) if facts.ok? }
  rescue Web::Error, JSON::ParserError
    failure(:error, "GitHub couldn't be reached. Try again in a minute.")
  end

  private
    def load
      response = get("/repos/#{@repo}")
      return facts(response.json) if response.ok? && response.json.is_a?(Hash)

      case response.status
      when 200..299 then failure(:error, "GitHub answered something this page can't read.")
      when 404 then failure(:not_found, "GitHub can't find #{@repo}. It may be private or the link may be wrong.")
      when 403, 429 then failure(:rate_limited, "GitHub's rate limit is used up.")
      else failure(:error, "GitHub answered with an error (#{response.status}). Try again in a minute.")
      end
    end

    def facts(body)
      Facts.new(status: :ok, full_name: body["full_name"], commits: commit_count, pushed_at: parse(body["pushed_at"]),
                stars: body["stargazers_count"].to_i, release: latest_release, message: nil)
    end

    # The last page number of a one-per-page listing. Unknown (nil) when GitHub won't say.
    def commit_count
      response = get("/repos/#{@repo}/commits?per_page=1")
      return 0 if response.status == 409 # an empty repository
      return unless response.ok?

      response.headers["link"].to_s[/[?&]page=(\d+)>; rel="last"/, 1]&.to_i || response.json.size
    rescue Web::Error, JSON::ParserError
      nil
    end

    def latest_release
      response = get("/repos/#{@repo}/releases/latest")
      return unless response.ok?

      body = response.json
      Release.new(tag: body["tag_name"], url: body["html_url"], published_at: parse(body["published_at"]),
                  assets: Array(body["assets"]).map { Asset.new(name: it["name"], size: it["size"].to_i) })
    rescue Web::Error, JSON::ParserError
      nil
    end

    def parse(time) = (Time.zone.parse(time.to_s) if time.present?)

    def get(path) = Web.get("#{Ship::Commits::API}#{path}", headers: Ship::Commits.headers)

    def failure(status, message) = Facts.new(status:, full_name: @repo, commits: nil, pushed_at: nil, stars: nil, release: nil, message:)
end
