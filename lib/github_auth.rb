require "net/http"

# Where GitHub API auth comes from, in order:
#   1. A GitHub App installation token (GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID and GITHUB_APP_PRIVATE_KEY or
#      GITHUB_APP_PRIVATE_KEY_PATH). Minted with an RS256 JWT, cached in Rails.cache until 5 minutes before it expires.
#   2. ENV["GITHUB_TOKEN"], then Rails credentials (github.token).
#   3. Nothing: unauthenticated, 60 calls an hour per IP.
# Never raises. A failed mint is logged by error class and status only (never the key or a token), then falls through.
module GithubAuth
  API = "https://api.github.com"
  CACHE_KEY = "github_auth/installation_token"
  REFRESH_MARGIN = 5.minutes

  def self.authorization(env: ENV, credentials: Rails.application.credentials, cache: Rails.cache, poster: method(:post), now: Time.current)
    token = installation_token(env:, cache:, poster:, now:) || env["GITHUB_TOKEN"].presence || (credentials.github || {})[:token].presence
    "Bearer #{token}" if token
  end

  def self.headers(**)
    authorization = authorization(**)
    authorization ? { "Authorization" => authorization } : {}
  end

  def self.app_configured?(env: ENV)
    env["GITHUB_APP_ID"].present? && env["GITHUB_APP_INSTALLATION_ID"].present? &&
      (env["GITHUB_APP_PRIVATE_KEY"].present? || env["GITHUB_APP_PRIVATE_KEY_PATH"].present?)
  end

  def self.installation_token(env:, cache:, poster:, now:)
    return unless app_configured?(env:)

    cached = cache.read(CACHE_KEY)
    return cached if cached

    status, body = poster.call("#{API}/app/installations/#{env["GITHUB_APP_INSTALLATION_ID"]}/access_tokens", jwt(env, now))
    unless status == 201
      Rails.logger.warn("GithubAuth: installation token request failed (status #{status})")
      return
    end
    data = JSON.parse(body)
    token = data["token"].presence
    expires_at = Time.zone.parse(data["expires_at"].to_s)
    return unless token && expires_at

    ttl = expires_at - REFRESH_MARGIN - now
    cache.write(CACHE_KEY, token, expires_in: ttl) if ttl.positive?
    token
  rescue StandardError => e
    Rails.logger.warn("GithubAuth: installation token failed (#{e.class})")
    nil
  end

  def self.jwt(env, now)
    key = OpenSSL::PKey::RSA.new(private_key(env))
    JWT.encode({ iat: now.to_i - 60, exp: now.to_i + 9.minutes.to_i, iss: env["GITHUB_APP_ID"].to_s }, key, "RS256")
  end

  def self.private_key(env)
    env["GITHUB_APP_PRIVATE_KEY"].presence&.gsub("\\n", "\n") || File.read(env["GITHUB_APP_PRIVATE_KEY_PATH"])
  end

  # Returns [status, body]. Network errors raise, and installation_token logs the class.
  def self.post(url, jwt)
    uri = URI(url)
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = true
    http.open_timeout = 4
    http.read_timeout = 6
    request = Net::HTTP::Post.new(uri, "Authorization" => "Bearer #{jwt}", "Accept" => "application/vnd.github+json",
                                       "X-GitHub-Api-Version" => "2022-11-28", "User-Agent" => "save-point.hackclub.com")
    response = http.start { |connection| connection.request(request) }
    [ response.code.to_i, response.body.to_s ]
  end
end
