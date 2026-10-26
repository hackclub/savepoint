require "test_helper"

class Ship::RepoFactsTest < ActiveSupport::TestCase
  teardown { Web.adapter = nil }

  def respond(status: 200, body: {}, headers: {}) = Web::Response.new(status:, headers:, body: body.to_json)

  # GitHub's answers for a repo with `commits` commits and an optional latest release.
  def github(release: nil, commits: 3)
    Web.adapter = lambda do |_method, url, _headers|
      case URI(url).path
      when "/repos/ana/pong" then respond(body: { full_name: "ana/pong", pushed_at: "2026-10-24T10:00:00Z", stargazers_count: 4 })
      when "/repos/ana/pong/commits" then respond(body: [ {} ], headers: { "link" => %(<https://api.github.com/repositories/1/commits?per_page=1&page=#{commits}>; rel="last") })
      when "/repos/ana/pong/releases/latest" then release ? respond(body: release) : respond(status: 404)
      else flunk "unexpected #{url}"
      end
    end
  end

  def facts = Ship::RepoFacts.new("https://github.com/ana/pong").fetch

  test "reads the name, commits, last push, stars and the latest release with its files" do
    github(release: { tag_name: "v1", html_url: "https://github.com/ana/pong/releases/tag/v1", published_at: "2026-10-01T00:00:00Z",
                      assets: [ { name: "pong.zip", size: 2048 } ] })

    assert_equal [ :ok, "ana/pong", 3, 4 ], facts.to_h.values_at(:status, :full_name, :commits, :stars)
    assert_equal Time.utc(2026, 10, 24, 10), facts.pushed_at
    assert_equal [ "v1", Time.utc(2026, 10, 1), [ Ship::RepoFacts::Asset.new("pong.zip", 2048) ] ], facts.release.to_h.values_at(:tag, :published_at, :assets)
  end

  test "a release that predates Save Point, or the first commit since it, is flagged" do
    github(release: { tag_name: "v1", html_url: "u", published_at: "2026-10-01T00:00:00Z", assets: [] })
    assert facts.release_predates?(nil), "before Save Point began"

    github(release: { tag_name: "v2", html_url: "u", published_at: (Program::STARTS_AT + 1.day).iso8601, assets: [] })
    assert_not facts.release_predates?(nil)
    assert_not facts.release_predates?(Program::STARTS_AT + 1.day - 1.hour), "after the first commit"
    assert facts.release_predates?(Program::STARTS_AT + 2.days), "before the first commit since the start"
  end

  test "no release is not a warning, and an empty repository has no commits" do
    github
    assert_nil facts.release
    assert_not facts.release_predates?(nil)

    Web.adapter = lambda do |_method, url, _headers|
      next respond(status: 409) if URI(url).path.end_with?("/commits")

      URI(url).path.end_with?("/releases/latest") ? respond(status: 404) : respond(body: { full_name: "ana/pong" })
    end
    assert_equal 0, facts.commits
  end

  test "plain messages for each failure, and a repository off GitHub" do
    { 404 => :not_found, 403 => :rate_limited, 500 => :error }.each do |code, status|
      Web.adapter = ->(*) { respond(status: code) }
      assert_equal status, facts.status
      assert facts.message.present?
    end
    Web.adapter = ->(*) { raise Web::Error, "boom" }
    assert_match(/couldn't be reached/, facts.message)
    assert_equal :not_github, Ship::RepoFacts.new("https://gitlab.com/a/b").fetch.status
  end
end
