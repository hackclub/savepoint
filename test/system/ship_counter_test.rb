require "application_system_test_case"

# D-096: after a first ship, the project page counts unshipped hours up to 5, then asks you to ship.
class ShipCounterTest < ApplicationSystemTestCase
  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @project = @user.project
    @project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
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

  test "before a first ship there is no counter" do
    log_hours(@user, 5.3)
    visit project_path

    assert_text "Your schedule"
    assert_no_selector ".project__ship-counter"
  end

  test "after a ship it counts up from that ship, with no ship button below 5" do
    ship!(1.0)
    log_hours(@user, 2.4)
    visit project_path

    within ".project__ship-counter" do
      assert_text "1.4 of 5 hours since your last ship"
      assert_no_link "Ship it"
    end
    assert_selector ".project__ship-counter[data-due='false']"
  end

  test "at 5 unshipped hours it asks you to ship and links to the ship page" do
    ship!(1.0)
    log_hours(@user, 6.3)
    visit project_path

    within ".project__ship-counter" do
      assert_text "5.3 hours built since your last ship. Time to ship it."
      click_link "Ship it"
    end
    assert_current_path project_ship_path
  end

  private
    def ship!(hours)
      @project.ships.new(title: "v1", description: "x" * 50, repo_url: "https://github.com/a/b", demo_url: "https://a.itch.io/b", hours:,
                         status: "approved", approved_hours: hours).save!(validate: false)
    end
end
