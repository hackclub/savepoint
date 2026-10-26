require "test_helper"

# /dev's controls on your own project (Dev::MyProject), and the fake Hackatime hours they pin.
class DevMyProjectTest < ActiveSupport::TestCase
  setup do
    @user = users(:orpheus)
    @project = projects(:orpheus)
    @project.update!(prize_key: "u2c", hackatime_projects: [ "rhythm-game" ])
    link_hackatime(@user)
    @pins = Rails.root.join("tmp/dev_pinned_hours_test_#{Process.pid}.json")
    @original = Hackatime::Fake.pin_file
    Hackatime::Fake.pin_file = @pins
    Hackatime.fake = true
    @mine = Dev::MyProject.new(@project)
  end

  teardown do
    Hackatime.fake = false
    Hackatime::Fake.pin_file = @original
    @pins.delete if @pins.exist?
  end

  test "the levels are percents of the goal's hours, rounded down to a tenth so 99% never reads as done" do
    assert_equal [ 0, 25, 50, 75, 99, 100, 130 ], Dev::MyProject::PERCENTS
    needed = @project.hours_needed
    assert_equal 0, @mine.hours_at(0)
    assert_equal needed, @mine.hours_at(100)
    assert_operator @mine.hours_at(99), :<, needed
    assert_operator @mine.hours_at(130), :>, needed
    assert_equal 4.9, Dev::MyProject.hours_at(5, 99)
  end

  test "setting logged hours makes hours_logged exactly that, and a sync keeps it" do
    Dev::MyProject.new(@project).set_logged!(@mine.hours_at(50))
    assert_equal @mine.hours_at(50).to_f, @project.reload.hours_logged

    travel_to Program::STARTS_AT + 3.days do
      StreakActivity.sync_for_user!(@user.reload)
      assert_equal @mine.hours_at(50).to_f, @project.reload.hours_logged, "the fake Hackatime says the same"
    end
  end

  test "a lot of hours spread over days, whatever the time zone" do
    @user.update!(timezone: "Asia/Tokyo")
    hours = @mine.hours_at(130) * 3
    @mine.set_logged!(hours)
    travel_to Program::ENDS_AT - 1.day do
      StreakActivity.sync_for_user!(@user.reload)
      assert_in_delta hours.to_f, @project.reload.hours_logged, 0.11
    end
  end

  test "back to the usual hours unpins them" do
    @mine.set_logged!(@mine.hours_at(100))
    assert_equal @project.hours_needed, @project.reload.hours_logged

    @mine.set_logged!(nil)
    assert_nil Hackatime::Fake.pinned_hours(@user)
    assert_equal 0, @project.reload.hours_logged
  end

  test "logged hours need the fake Hackatime" do
    Hackatime.fake = false
    assert_raises(RuntimeError) { @mine.set_logged!(1) }
  end

  test "setting approved hours makes hours_to_spend exactly that, and again changes the same ship" do
    @mine.set_approved!(@mine.hours_at(75))
    assert_equal @mine.hours_at(75).to_f, @project.reload.hours_to_spend

    @mine.set_approved!(@mine.hours_at(130))
    assert_equal @mine.hours_at(130).to_f, @project.reload.hours_to_spend
    assert_equal 1, @project.ships.where(title: Dev::MyProject::SHIP_TITLE).count
    assert @project.goal_reached?

    @mine.set_approved!(0)
    assert_equal 0, @project.reload.hours_to_spend
    assert_empty @project.ships
  end

  test "approved hours count what you've spent already, so what's left to spend is what the level says" do
    @mine.set_approved!(@project.hours_needed)
    @project.reload.orders.create!(prize_key: "aseprite")
    @mine.set_approved!(@mine.hours_at(50))

    assert_equal @mine.hours_at(50).to_f, @project.reload.hours_to_spend
  end

  test "resetting orders lets you claim again, and resetting the popup shows it again" do
    @mine.set_approved!(@project.hours_needed)
    @project.reload.orders.create!(prize_key: "u2c")
    @project.goal_reached_seen!

    @mine.reset_orders!
    @mine.reset_goal_popup!
    @project.reload
    assert_empty @project.orders
    assert_nil @project.goal_reached_seen_key
    assert @project.goal_reached_popup?
  end
end
