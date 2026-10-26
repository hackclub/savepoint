require "test_helper"

class GithubAuthTest < ActiveSupport::TestCase
  Credentials = Struct.new(:github)

  KEY = OpenSSL::PKey::RSA.generate(2048)
  NOW = Time.utc(2026, 10, 22, 12, 0, 0)
  APP = { "GITHUB_APP_ID" => "123", "GITHUB_APP_INSTALLATION_ID" => "456", "GITHUB_APP_PRIVATE_KEY" => KEY.to_pem }.freeze

  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @calls = []
  end

  def poster(status: 201, token: "ghs_app", expires_at: NOW + 1.hour)
    ->(url, jwt) { @calls << [ url, jwt ]; [ status, { token:, expires_at: expires_at.iso8601 }.to_json ] }
  end

  def auth(env, poster: poster(), credentials: Credentials.new(nil)) = GithubAuth.authorization(env:, credentials:, cache: @cache, poster:, now: NOW)

  test "mints an installation token with a signed JWT and caches it" do
    assert_equal "Bearer ghs_app", auth(APP)
    assert_equal "Bearer ghs_app", auth(APP)
    assert_equal 1, @calls.size
    url, jwt = @calls.first
    assert_equal "https://api.github.com/app/installations/456/access_tokens", url
    claims, header = JWT.decode(jwt, KEY.public_key, true, algorithm: "RS256", verify_expiration: false, verify_iat: false)
    assert_equal "RS256", header["alg"]
    assert_equal "123", claims["iss"]
    assert_equal NOW.to_i - 60, claims["iat"]
    assert_equal NOW.to_i + 540, claims["exp"]
  end

  test "accepts a key with literal backslash-n escapes" do
    assert_equal "Bearer ghs_app", auth(APP.merge("GITHUB_APP_PRIVATE_KEY" => KEY.to_pem.gsub("\n", "\\n")))
  end

  test "accepts a key file path" do
    path = Rails.root.join("tmp/github_auth_test_key.pem")
    File.write(path, KEY.to_pem)
    assert_equal "Bearer ghs_app", auth(APP.except("GITHUB_APP_PRIVATE_KEY").merge("GITHUB_APP_PRIVATE_KEY_PATH" => path.to_s))
  ensure
    FileUtils.rm_f(path)
  end

  test "does not cache a token that expires within 5 minutes" do
    auth(APP, poster: poster(expires_at: NOW + 4.minutes))
    assert_nil @cache.read(GithubAuth::CACHE_KEY)
  end

  test "falls back to GITHUB_TOKEN, then credentials" do
    assert_equal "Bearer pat_env", auth({ "GITHUB_TOKEN" => "pat_env" }, credentials: Credentials.new({ token: "pat_cred" }))
    assert_equal "Bearer pat_cred", auth({}, credentials: Credentials.new({ token: "pat_cred" }))
    assert_empty @calls
  end

  test "is unauthenticated with no configuration" do
    assert_nil auth({})
    assert_equal({}, GithubAuth.headers(env: {}, credentials: Credentials.new(nil), cache: @cache, now: NOW))
  end

  test "a failed mint falls back without raising or logging secrets" do
    logged = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)
    assert_equal "Bearer pat_env", auth(APP.merge("GITHUB_TOKEN" => "pat_env"), poster: poster(status: 401))
    assert_nil auth(APP, poster: ->(*) { raise Web::Error, "boom" })
    assert_nil auth(APP.merge("GITHUB_APP_PRIVATE_KEY" => "not a key"))
    assert_includes logged.string, "status 401"
    assert_not_includes logged.string, "BEGIN"
    assert_not_includes logged.string, "ghs_app"
  ensure
    Rails.logger = original
  end

  test "Ship::Commits.headers uses it" do
    assert_equal "application/vnd.github+json", Ship::Commits.headers["Accept"]
  end
end
