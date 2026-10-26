require "test_helper"

class Ship::ReadmeTest < ActiveSupport::TestCase
  teardown { Web.adapter = nil }

  def fetch(url = "https://github.com/a/b") = Ship::Readme.new(url).fetch

  test "asks GitHub for the rendered README and hands back its HTML" do
    Web.adapter = lambda do |_method, url, headers|
      assert_equal "https://api.github.com/repos/a/b/readme", url
      assert_equal "application/vnd.github.html", headers["Accept"]
      Web::Response.new(status: 200, headers: {}, body: "<h1>Pong</h1>")
    end
    result = fetch
    assert result.ok?
    assert_equal [ "<h1>Pong</h1>", "a/b" ], [ result.html, result.repo ]
  end

  test "a README is kept ten minutes, so a reviewer's reloads don't spend GitHub's limit" do
    # Swapped the way Ship::ChecklistTest swaps it: that test leaves Rails.cache as a singleton method, which `Rails.cache =` can't reach.
    original = Rails.cache
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.singleton_class.define_method(:cache) { cache }
    begin
      calls = 0
      Web.adapter = ->(_method, url, _headers) { calls += 1 if url.end_with?("/readme"); Web::Response.new(status: 200, headers: {}, body: "<p>hi</p>") }
      2.times { assert_equal "<p>hi</p>", fetch.html }
      assert_equal 1, calls

      Web.adapter = ->(*) { Web::Response.new(status: 404, headers: {}, body: "") }
      assert fetch("https://github.com/a/none").status == :missing
      assert_not cache.exist?([ "ship-readme", "a/none" ]), "a failure is never kept"
    ensure
      Rails.singleton_class.define_method(:cache) { original }
    end
  end

  test "says plainly why there is nothing to show" do
    assert_equal :not_github, fetch("https://gitlab.com/a/b").status
    { 404 => :missing, 403 => :rate_limited, 429 => :rate_limited, 500 => :error }.each do |code, status|
      Web.adapter = ->(*) { Web::Response.new(status: code, headers: {}, body: "") }
      result = fetch
      assert_not result.ok?
      assert_equal status, result.status
      assert result.message.present?
    end
    Web.adapter = ->(*) { raise Web::Error, "boom" }
    assert_match(/couldn't be reached/, fetch.message)
  end
end
