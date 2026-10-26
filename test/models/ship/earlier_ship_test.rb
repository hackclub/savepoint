require "test_helper"

class Ship::EarlierShipTest < ActiveSupport::TestCase
  teardown do
    Web.adapter = nil
    Ship::EarlierShip.token = nil
  end

  test "normalizes code urls" do
    assert_equal "github.com/a/b", Ship::EarlierShip.normalize("https://www.GitHub.com/A/B.git/tree/main")
  end

  test "without a key it says so and asks nobody" do
    Web.adapter = ->(*) { flunk "no request without a key" }
    result = Ship::EarlierShip.new("https://github.com/a/b").fetch
    assert_equal :not_configured, result.status
    assert_equal "Unified YSWS DB not configured", result.message
  end

  test "an own-program record is not an earlier ship, and the newest other one wins" do
    Ship::EarlierShip.token = "pat"
    Web.adapter = lambda do |_method, _url, headers|
      assert_equal "Bearer pat", headers["Authorization"]
      records = [ [ "Save Point", "2026-11-01" ], [ "jame gam", "2026-10-18" ], [ "Sleepover", "2026-10-27" ] ].map do |name, at|
        { "fields" => { "Code URL" => "https://github.com/a/b", "YSWS–Name" => [ name ], "Approved At" => at } }
      end
      records << { "fields" => { "Code URL" => "https://github.com/a/bc", "YSWS–Name" => [ "Other" ], "Approved At" => "2026-11-06" } }
      Web::Response.new(status: 200, headers: {}, body: { records: }.to_json)
    end
    result = Ship::EarlierShip.new("https://github.com/a/b").fetch
    assert result.found?
    assert_equal "Sleepover", result.entry.program
    assert_equal [ "jame gam", "Sleepover" ], result.entries.map(&:program), "every other program's record, oldest first"
    assert result.checked?
  end

  test "no match is none" do
    Ship::EarlierShip.token = "pat"
    Web.adapter = ->(*) { Web::Response.new(status: 200, headers: {}, body: { records: [] }.to_json) }
    result = Ship::EarlierShip.new("https://github.com/a/b").fetch
    assert_equal :none, result.status
    assert result.checked?
    assert_empty result.entries
  end

  test "errors are results" do
    Ship::EarlierShip.token = "pat"
    Web.adapter = ->(*) { Web::Response.new(status: 401, headers: {}, body: "") }
    assert_match(/refused/, Ship::EarlierShip.new("https://github.com/a/b").fetch.message)
    Web.adapter = ->(*) { raise Web::Error, "timeout" }
    assert_equal :error, Ship::EarlierShip.new("https://github.com/a/b").fetch.status
  end
end
