require "test_helper"

# D-099: an approved ship needs 1 new hour before the next one.
class ProjectShipMinimumTest < ActiveSupport::TestCase
  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @project = @user.project
    @project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Program::STARTS_AT + 3.hours, 360) ] } # 6.0 counted hours
    @user.update_column(:streak_synced_at, nil)
    StreakActivity.sync_for_user!(@user.reload)
    @project = Project.find(@project.id)
  end

  teardown { Hackatime.stubbed_spans = {} }

  def ship!(status, hours)
    @project.ships.new(title: "v1", description: "x" * 50, repo_url: "https://github.com/a/b", demo_url: "https://a.itch.io/b", hours:, **(status == "approved" ? approved_columns(hours) : { status: })).save!(validate: false)
    @project = Project.find(@project.id)
  end

  test "the minimum is one hour" do
    assert_equal 1, Project::SHIP_MINIMUM_NEW_HOURS
  end

  test "the first ship has no minimum" do
    assert_equal 0, @project.ship_hours_needed
    assert_not @project.ship_waiting?
    assert_nil @project.latest_approved_ship
  end

  test "an approved ship with under an hour of new time makes you wait for the rest" do
    ship!("approved", 5.5)
    assert_equal 0.5, @project.ship_hours_needed
    assert @project.ship_waiting?
    ship!("approved", 6)
    assert_equal 1.0, @project.ship_hours_needed
  end

  test "an hour or more of new time opens it" do
    ship!("approved", 5)
    assert_equal 0, @project.ship_hours_needed
    ship!("approved", 3)
    assert_not @project.ship_waiting?
  end

  test "a newest ship sent back for changes is exempt" do
    ship!("approved", 6)
    assert @project.ship_waiting?
    ship!("changes_needed", 6)
    assert_not @project.ship_waiting?
  end

  test "an earlier changes needed does not exempt a later approved ship" do
    ship!("changes_needed", 6)
    ship!("approved", 6)
    assert @project.ship_waiting?
  end
end
