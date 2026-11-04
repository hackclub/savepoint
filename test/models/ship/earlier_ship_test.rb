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

  # D-149: only a record of the same person whose covered dates meet the counted window is an overlap.
  def fetch_with(*records)
    Ship::EarlierShip.token = "pat"
    Web.adapter = lambda do |*|
      list = records.map { { "fields" => { "Code URL" => "https://github.com/a/b", "YSWS\u2013Name" => [ "jame gam" ], "Approved At" => "2026-10-31" }.merge(it) } }
      Web::Response.new(status: 200, headers: {}, body: { records: list }.to_json)
    end
    Ship::EarlierShip.new("https://github.com/a/b").fetch
  end

  test "D-149: ship 74's shape, the person's own record ending before the hours start, is no overlap" do
    result = fetch_with("Email" => "robin@example.com", "Override Hours Spent Justification" => "[HACKATIME]\nHackatime ID: not reported (jame gam)\nHackatime Projects: jame-gam-26 10/22/2026-10/25/2026")
    user = User.new(email: "Robin@example.com")
    assert_equal [ [ Date.new(2026, 10, 22), Date.new(2026, 10, 25) ] ], result.entry.ranges
    assert_nil result.overlapping_entry(user:, from: Date.new(2026, 10, 27), to: Date.new(2026, 11, 3))
  end

  test "D-149: a same-person record meeting the window is an overlap, by email or by Hackatime ID" do
    by_email = fetch_with("Email - Trimmed & Lowercased" => "robin@example.com", "Override Hours Spent Justification" => "[HACKATIME]\nHackatime ID: not reported\nHackatime Projects: g 10/22/2026-10/28/2026")
    assert by_email.overlapping_entry(user: User.new(email: "robin@example.com"), from: Date.new(2026, 10, 27), to: Date.new(2026, 11, 3))
    by_id = fetch_with("Override Hours Spent Justification" => "[HACKATIME]\nHackatime ID: 77\nHackatime Projects: g 10/22/2026-10/28/2026")
    assert by_id.overlapping_entry(user: User.new(email: "other@example.com", hackatime_uid: "77"), from: Date.new(2026, 10, 27), to: Date.new(2026, 11, 3))
  end

  test "D-149: a teammate's record overlapping in dates is no overlap" do
    result = fetch_with("Email" => "teammate@example.com", "Override Hours Spent Justification" => "[HACKATIME]\nHackatime ID: 99\nHackatime Projects: g 10/22/2026-10/30/2026")
    assert_nil result.overlapping_entry(user: User.new(email: "robin@example.com"), from: Date.new(2026, 10, 27), to: Date.new(2026, 11, 3))
  end

  test "D-149: a same-person record with no readable range is unknown, so it counts as an overlap" do
    result = fetch_with("Email" => "robin@example.com")
    assert_empty result.entry.ranges
    assert result.overlapping_entry(user: User.new(email: "robin@example.com"), from: Date.new(2026, 10, 27), to: Date.new(2026, 11, 3))
  end
end
