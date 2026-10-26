require "application_system_test_case"

# The NPS popup on the project page: it opens by itself for a participant who is due, Skip keeps it shut, and an answer
# is saved.
class NpsTest < ApplicationSystemTestCase
  setup do
    NpsResponse.asking = true
    @user = users(:orpheus)
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    log_hours(@user, 1)
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

  test "the popup opens, Send waits for the answers, and an answer is saved" do
    visit project_path
    assert_selector "dialog.nps-popup__dialog[open]", text: "How's Save Point going?"
    within "dialog.nps-popup__dialog" do
      assert_button "Send", disabled: true
      find("label.nps__box", text: "9").click
      fill_in "What are we doing well?", with: "The streaks"
      fill_in "What's something we can improve?", with: "More prizes"
      click_button "Send"
    end
    assert_no_selector "dialog[open]"
    assert_equal [ "daily", 9 ], NpsResponse.last.then { [ it.source, it.score ] }
    visit project_path
    assert_no_selector ".nps-popup", wait: 2
  end

  test "Skip keeps it shut on the next visit" do
    visit project_path
    within("dialog.nps-popup__dialog") { click_button "Skip" }
    assert_no_selector "dialog[open]"
    visit project_path
    assert_selector ".nps-popup", visible: :all
    assert_no_selector "dialog.nps-popup__dialog[open]", wait: 3
    assert_equal 0, NpsResponse.count
  end
end
