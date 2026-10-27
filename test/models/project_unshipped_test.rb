require "test_helper"

# D-096: the hours not yet covered by a ship.
class ProjectUnshippedTest < ActiveSupport::TestCase
  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @project = @user.project
    @project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Program::STARTS_AT + 3.hours, 360) ] }
    @user.update_column(:streak_synced_at, nil)
    StreakActivity.sync_for_user!(@user.reload)
    @project = Project.find(@project.id)
  end

  teardown { Hackatime.stubbed_spans = {} }

  def ship!(status, hours)
    @project.ships.new(title: "v1", description: "x" * 50, repo_url: "https://github.com/a/b", demo_url: "https://a.itch.io/b", hours:, status:).save!(validate: false)
    @project = Project.find(@project.id)
  end

  test "the threshold is 5 hours" do
    assert_equal 5, Project::SHIP_PROMPT_HOURS
  end

  test "with no ship, all the counted hours are unshipped" do
    assert_equal 6.0, @project.unshipped_hours
    assert @project.ship_prompt_due?
    assert_nil @project.latest_standing_ship
  end

  test "a pending ship covers its hours" do
    ship!("in_review", 4)
    assert_equal 2.0, @project.unshipped_hours
    assert_not @project.ship_prompt_due?
    ship!("awaiting_fraud", 5)
    assert_equal 1.0, @project.unshipped_hours
  end

  test "an approved ship covers its hours" do
    ship!("approved", 3.5)
    assert_equal 2.5, @project.unshipped_hours
  end

  test "a ship sent back for changes or rejected is not shipped" do
    ship!("changes_needed", 4)
    assert_equal 6.0, @project.unshipped_hours
    ship!("rejected", 5)
    assert_equal 6.0, @project.unshipped_hours
  end

  test "the latest standing ship counts, not an earlier one or a later rejected one" do
    ship!("approved", 2)
    ship!("in_review", 4)
    ship!("rejected", 6)
    assert_equal 2.0, @project.unshipped_hours
  end

  test "it never goes below 0" do
    ship!("approved", 9)
    assert_equal 0, @project.unshipped_hours
  end
end
