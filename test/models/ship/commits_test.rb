require "test_helper"

class Ship::CommitsTest < ActiveSupport::TestCase
  teardown { Web.adapter = nil }

  def fetch(url = "https://github.com/a/b") = Ship::Commits.new(url, since: Program::STARTS_AT, until_time: Program::STARTS_AT + 3.days).fetch

  test "lists commits and sends the dates" do
    Web.adapter = lambda do |_m, url, _h|
      assert_includes url, "/repos/a/b/commits"
      assert_includes url, "until="
      Web::Response.new(status: 200, headers: {}, body: [ { sha: "1234567890", html_url: "u", commit: { message: "First\nmore", author: { name: "A", date: "2026-11-12T00:00:00Z" } } } ].to_json)
    end
    result = fetch
    assert result.ok?
    assert_equal [ "1234567", "First" ], [ result.commits.first.sha, result.commits.first.message ]
  end

  test "plain messages for each failure" do
    assert_equal :not_github, fetch("https://gitlab.com/a/b").status
    { 404 => :not_found, 403 => :rate_limited, 500 => :error }.each do |code, status|
      Web.adapter = ->(*) { Web::Response.new(status: code, headers: {}, body: "{}") }
      assert_equal status, fetch.status
      assert fetch.message.present?
    end
    Web.adapter = ->(*) { raise Web::Error, "boom" }
    assert_match(/couldn't be reached/, fetch.message)
    Web.adapter = ->(*) { Web::Response.new(status: 409, headers: {}, body: "") }
    assert fetch.ok?
    assert_empty fetch.commits
  end
end
