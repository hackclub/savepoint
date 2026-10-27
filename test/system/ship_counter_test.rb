require "application_system_test_case"

# D-096: the project page counts unshipped hours up to 5, then asks you to ship.
class ShipCounterTest < ApplicationSystemTestCase
  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
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

  test "below 5 hours it counts up, with no ship button" do
    log_hours(@user, 2.4)
    visit project_path

    within ".project__ship-counter" do
      assert_text "2.4 of 5 hours since your last ship"
      assert_no_link "Ship it"
    end
    assert_selector ".project__ship-counter[data-due='false']"
    snap "below"
  end

  test "at 5 hours it asks you to ship and links to the ship page" do
    log_hours(@user, 5.3)
    visit project_path

    within ".project__ship-counter" do
      assert_text "5.3 hours built since your last ship. Time to ship it."
      click_link "Ship it"
    end
    assert_current_path project_ship_path
  end

  test "screenshots at 5 hours" do
    log_hours(@user, 5.3)
    visit project_path
    assert_selector ".project__ship-counter[data-due='true']"
    snap "due"
  end

  private
    def snap(name)
      [ [ 1280, 900, "desktop" ], [ 390, 844, "mobile" ] ].each do |width, height, label|
        page.current_window.resize_to(width, height)
        sleep 0.4
        execute_script('document.querySelector(".project__ship-counter").scrollIntoView({ block: "center" })')
        sleep 0.4
        page.save_screenshot("/tmp/shipshots/#{name}-#{label}.png")
      end
    end
end
