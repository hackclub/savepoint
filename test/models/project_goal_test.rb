require "test_helper"

# The goal prize: when your approved hours reach it (the earned-it popup, shown once per goal), the next prize up to
# offer, and what claiming a cheaper prize leaves of your hours.
class ProjectGoalTest < ActiveSupport::TestCase
  setup do
    @project = projects(:orpheus)
    @project.update!(prize_key: "u2c") # 8BitDo Ultimate 2C
    @goal = Prize.find("u2c")
  end

  test "the goal is reached once your approved hours to spend cover it, and not before" do
    assert_not @project.goal_reached?

    approve(@goal.hours - 0.5)
    assert_not @project.reload.goal_reached?
    assert_not @project.goal_reached_popup?

    approve(@goal.hours)
    assert @project.reload.goal_reached?
    assert @project.goal_reached_popup?
  end

  test "logged hours alone don't reach it: only approved ones do" do
    link_hackatime(users(:orpheus))
    @project.update!(hackatime_projects: [ "rhythm-game" ])
    users(:orpheus).streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: (@goal.hours * 3600).to_i)

    assert_equal @goal.hours, @project.reload.hours_logged
    assert_not @project.goal_reached?
  end

  test "the popup shows once per goal: seen for this goal, it stays quiet, and a new goal can show it again" do
    approve(Prize.find("steam100").hours)
    assert @project.reload.goal_reached_popup?

    @project.goal_reached_seen!
    assert_equal "u2c", @project.reload.goal_reached_seen_key
    assert @project.goal_reached?
    assert_not @project.goal_reached_popup?

    @project.update!(prize_key: "pro2")
    assert @project.reload.goal_reached_popup?, "a different goal, covered, shows its own popup"
    @project.goal_reached_seen!
    assert_not @project.reload.goal_reached_popup?
  end

  test "once you've claimed the goal there's nothing to claim, so no popup" do
    approve(@goal.hours + 20)
    @project.reload.orders.create!(prize_key: "u2c")

    assert @project.reload.goal_claimed?
    assert_not @project.goal_reached?
    assert_not @project.goal_reached_popup?
  end

  test "the upsell goes by cost, skips what you've claimed, and is nothing for the dearest prize" do
    dearer = Prize::ALL.select { |prize| prize.cost > @goal.cost }.min_by(&:cost)
    assert_equal dearer, @project.upsell_prize
    assert_operator @project.upsell_prize.hours, :>=, @goal.hours

    approve(100)
    @project.reload.orders.create!(prize_key: dearer.key)
    after = Prize::ALL.select { |prize| prize.cost > @goal.cost && prize != dearer }.min_by(&:cost)
    assert_equal after, @project.reload.upsell_prize

    @project.update!(prize_key: "steam100")
    assert_nil @project.upsell_prize, "nothing costs more than the $100 card"
    assert_nil Project.new.upsell_prize, "no goal, no upsell"
  end

  test "claiming a cheaper prize spends its hours, keeps the goal, and leaves the rest to spend and to go" do
    approve(@goal.hours)
    cheaper = Prize.find("aseprite")
    @project.reload.orders.create!(prize_key: cheaper.key)
    @project.reload

    assert_equal "u2c", @project.prize_key
    assert_in_delta @goal.hours - cheaper.hours, @project.hours_to_spend, 0.01
    assert_not @project.goal_reached?, "what's left no longer covers the goal"
    assert_in_delta cheaper.hours, @project.hours_spent, 0.01
  end

  private
    # Approved hours for a ship: the most of any approved ship (Project#hours_approved).
    def approve(hours)
      ship = @project.ships.find_or_initialize_by(title: "Beat Sheet")
      ship.assign_attributes(description: "A rhythm game where every cell is a drum pad, and it is a game.", repo_url: "https://github.com/orpheus/beat-sheet",
                             demo_url: "https://beat.sheet", hours:, screenshot_shows_game: true)
      ship.screenshot.attach(Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")) unless ship.screenshot.attached?
      ship.save!
      ship.update_columns(status: "approved", approved_hours: hours)
      @project.ships.reset
    end
end
