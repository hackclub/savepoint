require "test_helper"

class HackatimeFakeTest < ActiveSupport::TestCase
  test "the fake Hackatime is off in test unless a test turns it on" do
    assert_not Hackatime.fake
  end

  test "when on, anyone gets fake projects to pick and fake building time, with no API" do
    user = users(:orpheus)
    link_hackatime(user)
    Hackatime.fake = true
    names = Hackatime.pickable_projects(user).map(&:name)
    assert_includes names, "moonlit-platformer"
    assert_includes names, "dotfiles", "old projects are listed too (D-089)"
    assert_equal 0, Hackatime.pickable_projects(user).find { |pick| pick.name == "dotfiles" }.seconds, "with no time that counts"

    travel_to Program::STARTS_AT + 3.days
    spans = Hackatime.heartbeat_spans(user, [ "moonlit-platformer" ], start_date: Program::HACKATIME_START, end_date: Program.today + 1)
    assert spans.any?
    assert_empty Hackatime.heartbeat_spans(user, [ "not-a-project" ], start_date: Program::HACKATIME_START, end_date: Program.today + 1)
    assert Hackatime.user_id("any-token").start_with?("fake-")
  ensure
    Hackatime.fake = false
  end

  test "the fake gives everyone a trust level, blue unless /dev set another" do
    user = users(:orpheus)
    link_hackatime(user)
    Hackatime.fake = true
    Hackatime::Fake.trust_file = Rails.root.join("tmp/test_trust_levels.json")
    assert_equal "blue", Hackatime.refresh_trust_level!(user)

    Hackatime::Fake.set_trust_level!(user, "red")
    assert_equal "red", Hackatime.refresh_trust_level!(user)
    assert user.reload.hackatime_banned?
  ensure
    Hackatime::Fake.trust_file.delete if Hackatime::Fake.trust_file.exist?
    Hackatime::Fake.trust_file = Rails.root.join("tmp/dev_trust_levels.json")
    Hackatime.fake = false
  end
end
