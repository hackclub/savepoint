require "test_helper"

# The project page's "you've earned it" popup, the note on the hours bar, and noting the popup was shown (GoalSeensController).
class GoalPopupTest < ActionDispatch::IntegrationTest
  setup do
    # Fixed clock on day 2, so nothing depends on the real one: Program::DATES begins on the launch day, and every
    # sign-in or page view syncs the days from then up to today from Hackatime's spans (StreakActivity.sync_for_user!).
    travel_to Time.utc(2026, 10, 24, 12)
    @spans_before = Hackatime.stubbed_spans
    @user = users(:orpheus)
    @project = projects(:orpheus)
    link_hackatime(@user)
    @project.update!(prize_key: "u2c", hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    @goal = Prize.find("u2c")
    @upsell = @project.upsell_prize
    mock_hack_club_auth(uid: @user.hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    post "/auth/hackclub"
    follow_redirect!
  end

  teardown { Hackatime.stubbed_spans = @spans_before }

  test "approved hours that cover the goal open the popup on the project page, with the claim and an upsell" do
    approve(@goal.hours + 1)
    get project_path

    assert_response :success
    assert_select "[data-controller~=goal-popup][data-goal-popup-seen-url-value=?]", project_goal_seen_path
    assert_select "dialog.order-sheet--goal" do
      assert_select ".order-sheet__name", "You've earned the #{@goal.name}!"
      assert_select ".order-sheet__rays"
      assert_select "button[data-action=?]", "prize-sheet#claim", text: "Claim it"
      assert_select "button", text: "Not now"
      assert_select ".goal-popup__upsell" do
        assert_select ".goal-popup__upsell-text", /Or keep going for the #{Regexp.escape(@upsell.name)}/
        assert_select ".goal-popup__upsell-text b", "#{@project.reload.then { |p| helpers_hours((@upsell.hours - p.hours_to_spend).round(1)) }} more hrs"
        assert_select "form[action=?] input[name=_method][value=patch]", project_path
        assert_select "form input[name=?][value=?]", "project[prize_key]", @upsell.key
        assert_select "button", text: "Keep going"
      end
      assert_select "form[action=?]", shop_order_path do
        assert_select "input[name=?][value=?]", "order[prize_key]", @goal.key
        assert_select "input[name=preferred_name]"
        assert_select "input[name='address[street_address]'][value=?]", "15 Falls Rd"
        assert_select "input[name='address[country]']"
      end
    end
    assert_select ".project__track-note", 0, "approved, so nothing to ship"
  end

  test "no upsell when nothing costs more than the goal" do
    @project.update!(prize_key: "steam100")
    approve(Prize.find("steam100").hours)
    get project_path

    assert_select "dialog.order-sheet--goal"
    assert_select ".goal-popup__upsell", 0
  end

  test "no popup before the hours are approved, after it was seen, or once the goal is claimed" do
    get project_path
    assert_select "dialog.order-sheet--goal", 0

    approve(@goal.hours)
    @project.reload.goal_reached_seen!
    get project_path
    assert_select "dialog.order-sheet--goal", 0

    @project.update_column(:goal_reached_seen_key, nil)
    @project.orders.create!(prize_key: "u2c")
    get project_path
    assert_select "dialog.order-sheet--goal", 0
  end

  test "logged enough but not approved: a note on the hours bar, and no popup" do
    log(@goal.hours)
    get project_path

    assert_select ".project__track-note", "You've logged enough. Ship it to unlock the #{@goal.name}."
    assert_select "dialog.order-sheet--goal", 0
  end

  test "no note while the logged hours fall short, or once the approved ones cover it" do
    get project_path
    assert_select ".project__track-note", 0

    approve(@goal.hours)
    get project_path
    assert_select ".project__track-note", 0
  end

  test "showing the popup notes it for this goal, once" do
    approve(@goal.hours)
    post project_goal_seen_path
    assert_response :no_content
    assert_equal "u2c", @project.reload.goal_reached_seen_key

    @project.update!(prize_key: "pro2")
    post project_goal_seen_path # not reached for pro2: nothing to note
    assert_equal "u2c", @project.reload.goal_reached_seen_key
  end

  test "without a project there's nothing to note" do
    @user.project.destroy!
    post project_goal_seen_path
    assert_response :not_found
  end

  test "the bar and the pace use what's left after claiming a cheaper prize" do
    log(@goal.hours)
    approve(@goal.hours)
    cheaper = Prize.find("aseprite")
    @project.reload.orders.create!(prize_key: cheaper.key)
    get project_path

    left = (@goal.hours - cheaper.hours).round(1)
    assert_equal "u2c", @project.reload.prize_key, "the goal stays"
    assert_select ".project__track-count", helpers_hours(left)
    assert_select ".project__track-spent", /#{helpers_hours(cheaper.hours)} spent in the shop/
    assert_select ".project__track-note", 0, "what's left doesn't cover the goal, so there's nothing to ship"
    assert_select "dialog.order-sheet--goal", 0
  end

  private
    def helpers_hours(hours) = hours.to_s.delete_suffix(".0")

    # Hackatime says Orpheus built this long on the first day, and the next sync turns that into the day's hours.
    def log(hours)
      span = hackatime_span(Program::STARTS_AT + 3.hours, (hours * 60).ceil)
      Hackatime.stubbed_spans = Hackatime.stubbed_spans.merge(@user.hackatime_uid => [ span ])
      @user.update_column(:streak_synced_at, nil)
      StreakActivity.sync_for_user!(@user.reload)
    end

    def approve(hours)
      log(hours)
      ship = @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, and it is a game.",
                                    repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours:,
                                    screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
      ship.update_columns(approved_columns(hours))
      @project.ships.reset
    end
end
