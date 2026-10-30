require "test_helper"

class Ship::ChecklistTest < ActiveSupport::TestCase
  teardown { Web.adapter = nil }

  def answer(map) = (Web.adapter = ->(_m, url, _h) { map.find { |pattern, _| url.match?(pattern) }&.last || Web::Response.new(status: 404, headers: {}, body: "") })
  def ok(body = "{}") = Web::Response.new(status: 200, headers: {}, body:)
  def readme(text) = ok({ encoding: "base64", content: Base64.encode64(text) }.to_json)

  test "a public repo with a README, a loading demo and commits passes everything" do
    answer(%r{\Ahttps://api\.github\.com/repos/a/b/commits} => ok([ { sha: "abcdefg1", commit: { message: "m", author: { date: "2026-11-12T00:00:00Z" } } } ].to_json),
           %r{\Ahttps://api\.github\.com/repos/a/b/readme\z} => readme("Play it: https://example.com/play"), %r{\Ahttps://api\.github\.com/repos/a/b\z} => ok({ private: false }.to_json), %r{\Ahttps://example\.com/} => ok)
    checks = Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play")
    assert_equal %i[ok ok ok ok ok], checks.items.map(&:state)
    assert_not checks.blocked?
  end

  test "private repo and a dead demo block, and the README waits" do
    answer(%r{\Ahttps://api\.github\.com/repos/a/b\z} => ok({ private: true }.to_json))
    checks = Ship::Checklist.new(repo_url: "https://github.com/a/b", demo_url: "https://example.com/gone")
    assert_equal %i[fail wait wait fail wait], checks.items.map(&:state)
    assert checks.blocked?
  end

  test "a check that could not run never blocks" do
    answer(%r{\Ahttps://api\.github\.com/} => Web::Response.new(status: 403, headers: {}, body: "{}"), %r{\Ahttps://example\.com/?\z} => ok)
    checks = Ship::Checklist.new(repo_url: "https://github.com/a/b", demo_url: "https://example.com")
    assert_equal :unchecked, checks.items.first.state
    assert_not checks.blocked?
  end

  test "an empty form waits" do
    checks = Ship::Checklist.new(repo_url: "", demo_url: "")
    assert_equal %i[wait wait wait wait wait], checks.items.map(&:state)
  end

  def readme_items(text, demo, status: 200)
    answer(%r{\Ahttps://api\.github\.com/repos/a/b/readme\z} => status == 200 ? readme(text) : Web::Response.new(status:, headers: {}, body: ""),
           %r{\Ahttps://api\.github\.com/repos/a/b\z} => ok({ private: false }.to_json), %r{\Ahttps://api\.github\.com/repos/a/b/commits} => ok("[]"),
           %r{\Ahttps://example\.com(/|\z)} => ok)
    Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: demo).items.index_by(&:key)
  end

  test "the README has to contain the playable link (D-019)" do
    assert_equal :ok, readme_items("Play: https://example.com/play", "https://example.com/play")[:readme_demo].state
    missing = readme_items("A game.", "https://example.com/play")[:readme_demo]
    assert_equal :fail, missing.state
    assert missing.blocker
    assert_includes missing.detail, "https://example.com/play"
  end

  test "the README match ignores the scheme, the host's case and a trailing slash" do
    [ "http://example.com/play", "example.com/play", "https://EXAMPLE.com/play/", "[play](https://Example.COM/play)" ].each do |text|
      assert Ship::Checklist.mentions_link?(text, "https://example.com/play"), text
    end
    assert Ship::Checklist.mentions_link?("see https://example.com/", "example.com")
    assert Ship::Checklist.mentions_link?("see https://example.com/play?level=2 now", "https://example.com/play?level=2")
  end

  test "the README only has to contain the link, anywhere in it" do
    [ "https://example.com/play2", "https://example.com/play/extra", "https://www.example.com/play", "<a href=\"https://example.com/play\">" ].each do |text|
      assert Ship::Checklist.mentions_link?(text, "https://example.com/play"), text
    end
    [ "https://example.com/Play", "https://example.org/play", "example.com" ].each do |text|
      assert_not Ship::Checklist.mentions_link?(text, "https://example.com/play"), text
    end
  end

  test "no README, or one that can't be read, doesn't error: it waits or can't be checked" do
    assert_equal :wait, Ship::Checklist.new(repo_url: "", demo_url: "https://example.com/play").items.index_by(&:key)[:readme_demo].state
    assert_equal :wait, readme_items("", "")[:readme_demo].state
    assert_equal :wait, readme_items("", "https://example.com/play", status: 404)[:readme_demo].state, "the README check says it's missing"
    assert_equal :unchecked, readme_items("", "https://example.com/play", status: 403)[:readme].state
    assert_equal :unchecked, readme_items("", "https://example.com/play", status: 403)[:readme_demo].state
  end

  test "only a README certainly without the playable link blocks a ship" do
    answer(%r{/readme\z} => readme("A game."))
    assert Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play").readme_without_demo?
    answer(%r{/readme\z} => readme("https://example.com/play"))
    assert_not Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play").readme_without_demo?
    answer(%r{/readme\z} => Web::Response.new(status: 404, headers: {}, body: ""))
    assert Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play").readme_without_demo?, "no README at all"
    answer(%r{/readme\z} => Web::Response.new(status: 502, headers: {}, body: ""))
    assert_not Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play").readme_without_demo?, "couldn't read it"
    Web.adapter = nil
    assert_not Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play").readme_without_demo?, "network off"
  end

  test "what GitHub or the host couldn't answer is unchecked: not a blocker, nothing to show (D-022)" do
    [ 403, 429, 500, 502 ].each do |status|
      answer(%r{\Ahttps://api\.github\.com/} => Web::Response.new(status:, headers: {}, body: "{}"), %r{\Ahttps://example\.com(/|\z)} => ok)
      checks = Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play")
      assert_equal %i[unchecked unchecked unchecked ok unchecked], checks.items.map(&:state), "GitHub answered #{status}"
      assert checks.items.none? { it.blocker && it.state == :fail }
      assert_not checks.blocked?
      assert checks.items.select { it.state == :unchecked }.all? { it.detail.nil? }, "nothing for the participant to read"
    end
  end

  test "the playable link: a timeout is unchecked, a real 404 or 500 from its host is a failure" do
    github = { %r{\Ahttps://api\.github\.com/repos/a/b\z} => ok({ private: false }.to_json) }
    Web.adapter = ->(_m, url, _h) { URI(url).host == "example.com" ? raise(Web::Timeout, "execution expired") : (github.find { |p, _| url.match?(p) }&.last || ok("{}")) }
    assert_equal :unchecked, Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play").items.index_by(&:key)[:demo].state

    [ 404, 500 ].each do |status|
      answer(%r{\Ahttps://example\.com(/|\z)} => Web::Response.new(status:, headers: {}, body: ""))
      demo = Ship::Checklist.new(repo_url: "", demo_url: "https://example.com/play").items.index_by(&:key)[:demo]
      assert_equal :fail, demo.state, "the host answered #{status}"
      assert demo.blocker
    end
    Web.adapter = ->(_m, _u, _h) { raise Web::Error, "example.com does not exist" }
    assert_equal :fail, Ship::Checklist.new(repo_url: "", demo_url: "https://example.com/play").items.index_by(&:key)[:demo].state
  end

  test "answers are cached by repository and by link: definite ones for 10 minutes, failures for 1, unchecked ones not at all" do
    store = ActiveSupport::Cache::MemoryStore.new
    original = Rails.cache
    Rails.singleton_class.define_method(:cache) { store }
    calls = []
    Web.adapter = lambda do |_m, url, _h|
      calls << url
      url.match?(%r{/readme\z}) ? readme("https://example.com/play") : (url.include?("/commits") ? ok("[]") : (url.end_with?("/b") ? ok({ private: false }.to_json) : ok))
    end
    Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play").items
    first = calls.size
    Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/play").items
    assert_equal first, calls.size, "the same links again ask nothing"
    Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://example.com/other").items
    assert_equal first + 2, calls.size, "a new link asks about the link and re-reads the README (it may have the link now): the repository and commits answers stand"

    calls.clear
    Web.adapter = ->(_m, url, _h) { calls << url; Web::Response.new(status: 503, headers: {}, body: "{}") }
    2.times { Ship::Checklist.new(repo_url: "github.com/c/d", demo_url: "").items }
    assert_equal 2, calls.size, "unchecked answers aren't kept: each try asks again"
  ensure
    Rails.singleton_class.define_method(:cache) { original }
  end

  def with_memory_cache
    store = ActiveSupport::Cache::MemoryStore.new
    original = Rails.cache
    Rails.singleton_class.define_method(:cache) { store }
    yield
  ensure
    Rails.singleton_class.define_method(:cache) { original }
  end

  def readme_world(calls, text_box, readme_status: 200)
    Web.adapter = lambda do |_m, url, _h|
      calls << url
      if url.match?(%r{/readme\z}) then readme_status == 200 ? readme(text_box.first) : Web::Response.new(status: readme_status, headers: {}, body: "{}")
      elsif url.include?("/commits") then ok("[]")
      elsif url.end_with?("/b") then ok({ private: false }.to_json)
      else ok
      end
    end
  end

  test "the README is read again after the link was missing: the participant fixes it and comes back" do
    with_memory_cache do
      calls = []
      text = [ "A game." ]
      readme_world(calls, text)
      check = -> { Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://kocio07.itch.io/tnpgxd").items.index_by(&:key) }
      assert_equal :fail, check.call[:readme_demo].state
      text[0] = "Play here -> https://kocio07.itch.io/tnpgxd"
      assert_equal :ok, check.call[:readme_demo].state, "no waiting for the cache to expire"
      assert_equal 2, calls.count { it.end_with?("/readme") }
      assert_equal 1, calls.count { it.include?("/commits") }, "the commits are not asked again"
      assert_equal 1, calls.count { it.end_with?("/a/b") }, "the repository is not asked again"
      check.call
      assert_equal 2, calls.count { it.end_with?("/readme") }, "a README with the link is kept"
    end
  end

  test "a new playable link next to an old one is found once the README has it" do
    with_memory_cache do
      calls = []
      text = [ "Old: https://jamegam.example/old" ]
      readme_world(calls, text)
      checks = ->(demo) { Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: demo).items.index_by(&:key)[:readme_demo].state }
      assert_equal :ok, checks.call("https://jamegam.example/old")
      assert_equal :fail, checks.call("https://x.itch.io/new")
      text[0] += "\nPlay: https://x.itch.io/new"
      assert_equal :ok, checks.call("https://x.itch.io/new")
      assert_equal :ok, checks.call("https://jamegam.example/old")
    end
  end

  test "no re-read while the playable link is missing or isn't a link yet, and a README that can't be re-read never blocks" do
    with_memory_cache do
      calls = []
      text = [ "A game." ]
      readme_world(calls, text)
      3.times { Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "").items }
      assert_equal 1, calls.count { it.end_with?("/readme") }
      readme_world(calls, text, readme_status: 503)
      item = Ship::Checklist.new(repo_url: "github.com/a/b", demo_url: "https://x.itch.io/new").items.index_by(&:key)[:readme_demo]
      assert_equal :unchecked, item.state
      assert_not item.blocker && item.state == :fail
    end
  end

  test "the link is found in the README text of the two reports" do
    assert Ship::Checklist.mentions_link?("Play here -> https://kocio07.itch.io/tnpgxd", "https://kocio07.itch.io/tnpgxd")
    both = "old https://jamegam.hackclub.com/x and new https://z.itch.io/g"
    assert Ship::Checklist.mentions_link?(both, "https://z.itch.io/g")
    assert Ship::Checklist.mentions_link?(both, "https://jamegam.hackclub.com/x")
  end
end
