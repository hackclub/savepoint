require "test_helper"

class UserTimezoneTest < ActiveSupport::TestCase
  test "a legacy name maps to its canonical zone" do
    assert_equal "Asia/Kolkata", UserTimezone.name("Asia/Calcutta")
    assert_equal "Asia/Kathmandu", UserTimezone.name("Asia/Katmandu")
    assert_equal "America/Argentina/Buenos_Aires", UserTimezone.name("America/Buenos_Aires")
    assert_equal "Asia/Ho_Chi_Minh", UserTimezone.name("Asia/Saigon")
    assert_equal "Asia/Yangon", UserTimezone.name("Asia/Rangoon")
    assert_equal "Europe/Kyiv", UserTimezone.name("Europe/Kiev")
    assert_equal "Asia/Kolkata", UserTimezone.zone("Asia/Calcutta").tzinfo.identifier
  end

  test "a current name passes through" do
    assert_equal "America/New_York", UserTimezone.name("America/New_York")
  end

  test "garbage, blank and nil fall back to UTC instead of raising" do
    [ "Not/AZone", "garbage", "", "  ", nil ].each do |raw|
      assert_equal "UTC", UserTimezone.name(raw)
      assert_equal "UTC", UserTimezone.zone(raw).name
    end
  end

  test "streak_date_for does not raise for a garbage zone, and counts the day in UTC" do
    time = Time.utc(2026, 10, 25, 1, 30)
    assert_equal Date.new(2026, 10, 24), StreakActivity.streak_date_for(time, "Not/AZone")
    assert_equal Date.new(2026, 10, 25), StreakActivity.streak_date_for(time, "Asia/Calcutta")
  end
end
