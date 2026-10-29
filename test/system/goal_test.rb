require "application_system_test_case"

# Reaching your goal prize: the popup on the project page (claim it, or keep going for the next one up), and claiming a
# cheaper prize from the shop while the goal stays.
class GoalTest < ApplicationSystemTestCase
  setup do
    @user = users(:orpheus)
    @project = @user.project
    link_hackatime(@user)
    @project.update!(prize_key: "u2c", hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    @goal = Prize.find("u2c")
    mock_hack_club_auth(uid: @user.hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    visit onboarding_path
    execute_script(<<~JS)
      const form = document.createElement("form")
      form.method = "post"
      form.action = "/auth/hackclub"
      document.body.append(form)
      form.submit()
    JS
    assert_current_path onboarding_path
  end

  test "reaching the goal opens the popup once, and Claim it goes through the parcel name to the order" do
    approve(@goal.hours + 3)
    visit project_path

    assert_selector "dialog.order-sheet--goal[open]", text: "You've earned the #{@goal.name}!"
    assert_selector ".goal-popup__upsell", text: "Or keep going for the #{@project.upsell_prize.name}"
    wait_for_sheet "dialog.order-sheet--goal"
    within "dialog.order-sheet--goal" do
      click_button "Claim it"
      assert_field "Name for the parcel", with: @user.reload.name
      assert_text "3 hrs left after claiming"
      assert_field "City or town", with: "Shelburne"
      fill_in "Street address", with: "1 Elm St"
      fill_in "Name for the parcel", with: "Orph D"
      click_button "Claim it"
      assert_text "Claimed!"
    end

    assert_selector "#shop-#{@goal.key}[data-state=claimed]"
    assert_selector ".shop__notice", text: "You claimed the #{@goal.name}"
    order = @project.reload.orders.last
    assert_equal [ "u2c", "Orph D", "1 Elm St", "Shelburne" ], [ order.prize_key, order.recipient_name, order.address["street_address"], order.address["locality"] ]
    assert_in_delta 3, @project.hours_to_spend, 0.01

    visit project_path
    assert_no_selector "dialog.order-sheet--goal[open]", wait: 2
  end

  test "the popup doesn't open again for the same goal once it was shown, and Not now closes it" do
    approve(@goal.hours)
    visit project_path
    assert_selector "dialog.order-sheet--goal[open]"
    wait_for_sheet "dialog.order-sheet--goal"
    click_button "Not now"
    assert_no_selector "dialog.order-sheet--goal[open]"
    assert_equal "u2c", @project.reload.goal_reached_seen_key

    visit project_path
    assert_no_selector "dialog.order-sheet--goal[open]", wait: 2
  end

  test "Keep going makes the next prize up the goal and closes the popup" do
    approve(@goal.hours)
    upsell = @project.upsell_prize
    visit project_path
    assert_selector "dialog.order-sheet--goal[open]"
    wait_for_sheet "dialog.order-sheet--goal"
    within("dialog.order-sheet--goal") { click_button "Keep going" }

    assert_no_selector "dialog.order-sheet--goal" # the form waits 300 ms for its sound, then the page reloads on the new goal
    assert_equal upsell.key, @project.reload.prize_key
    assert_empty @project.orders
  end

  test "claiming a cheaper prize from the shop spends its hours, keeps the goal, and the bar counts what's left" do
    approve(@goal.hours)
    cheaper = Prize.find("aseprite")
    visit shop_path

    assert_selector "#shop-#{cheaper.key}[data-state=ready]"
    find("#shop-#{cheaper.key} > button.shop-card").click
    wait_for_sheet "#shop-#{cheaper.key} dialog"
    within "#shop-#{cheaper.key} dialog" do
      click_button "Claim it"
      click_button "Claim it"
      assert_text "Claimed!"
    end

    assert_selector "#shop-#{cheaper.key}[data-state=claimed]", wait: 8 # the sheet holds "Claimed!" for 1.5 s, then the page goes to the shop
    assert_selector "#shop-#{@goal.key}.shop-prize--goal"
    left = (@goal.hours - cheaper.hours).round(1)
    assert_selector "#shop-#{@goal.key}[data-state=locked]", text: "#{cheaper.hours.to_s.delete_suffix(".0")} more hr"
    assert_equal "u2c", @project.reload.prize_key
    assert_in_delta left, @project.hours_to_spend, 0.01

    visit project_path
    assert_selector ".project__track-count", text: left.to_s.delete_suffix(".0")
    assert_selector ".project__track-spent", text: "#{cheaper.hours.to_s.delete_suffix(".0")} spent in the shop"
    assert_no_selector "dialog.order-sheet--goal[open]", wait: 2
  end

  private
    # Approved hours are logged ones: put them on the first program day, then an approved ship holds them.
    def approve(hours)
      log_hours(@user, hours)
      ship = @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, and it is a game.",
                                    repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours:,
                                    screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
      ship.update_columns(approved_columns(hours))
    end
end
