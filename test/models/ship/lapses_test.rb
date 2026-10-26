require "test_helper"

class Ship::LapsesTest < ActiveSupport::TestCase
  setup do
    @key = ENV["HACKATIME_ADMIN_API_KEY"]
    @user = users(:orpheus)
    link_hackatime(@user)
    @window = Program::STARTS_AT..(Program::STARTS_AT + 2.days)
  end

  teardown do
    ENV["HACKATIME_ADMIN_API_KEY"] = @key
    Web.adapter = nil
  end

  def lapses = Ship::Lapses.new(@user, [ "rhythm-game" ], @window).fetch

  test "without the admin key the list is unavailable, and nothing is asked" do
    ENV["HACKATIME_ADMIN_API_KEY"] = nil
    Web.adapter = ->(*) { flunk "no request without a key" }
    assert_match(/admin API key/, lapses.error)
    assert_empty lapses.lapses
  end

  test "lists each Lapse on the linked projects, with its link and length" do
    ENV["HACKATIME_ADMIN_API_KEY"] = "admin-key"
    Web.adapter = lambda do |_method, url, headers|
      uri = URI(url)
      if uri.path.end_with?("/user/heartbeats")
        assert_equal "Bearer admin-key", headers["Authorization"]
        query = Rack::Utils.parse_query(uri.query)
        assert_equal [ "1001", "rhythm-game", "Lapse", @window.begin.to_i.to_s ], query.values_at("user_id", "project", "language", "start_date")
        Web::Response.new(status: 200, headers: {}, body: { heartbeats: [ { entity: "Boss art (abc123xyz)" }, { entity: "Boss art (abc123xyz)" }, { entity: "no id" } ], has_more: false }.to_json)
      else
        Web::Response.new(status: 200, headers: {}, body: { data: { timelapse: { name: "Boss art", duration: 1800, visibility: "PUBLIC" } } }.to_json)
      end
    end

    result = lapses
    assert_nil result.error
    assert_equal [ "abc123xyz", "Boss art", 1800, "https://lapse.hackclub.com/timelapse/abc123xyz" ], result.lapses.first.to_h.values_at(:id, :title, :duration, :url)
    assert_equal 1, result.lapses.size, "the same Lapse once"
    assert_equal 1800, result.seconds
  end

  test "a Lapse that failed processing or is gone is left out, and a failure says so without raising" do
    ENV["HACKATIME_ADMIN_API_KEY"] = "admin-key"
    Web.adapter = lambda do |_method, url, _headers|
      if URI(url).path.end_with?("/user/heartbeats")
        Web::Response.new(status: 200, headers: {}, body: { heartbeats: [ { entity: "A (aaaaaa11)" }, { entity: "B (bbbbbb22)" } ] }.to_json)
      elsif url.include?("aaaaaa11")
        Web::Response.new(status: 200, headers: {}, body: { data: { timelapse: { name: "A", duration: 10, visibility: "FAILED_PROCESSING" } } }.to_json)
      else
        Web::Response.new(status: 404, headers: {}, body: "{}")
      end
    end
    assert_empty lapses.lapses

    Web.adapter = ->(*) { raise Web::Error, "boom" }
    assert_match(/couldn't be reached/, lapses.error)
  end
end
