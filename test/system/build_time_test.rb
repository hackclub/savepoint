require "application_system_test_case"

# Changing when you build, from the pace editor on the project page.
class BuildTimeTest < ApplicationSystemTestCase
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

  test "picking a build time in the pace editor saves it" do
    visit project_path(edit: "pace")
    within ".project__build-times" do
      assert_selector "button[aria-pressed=true]", text: "evening"
      click_button "late night"
    end

    assert_no_selector ".project__build-times"
    assert_equal "late night", @user.project.reload.build_time
    visit project_path(edit: "pace")
    assert_selector ".project__build-times button[aria-pressed=true]", text: "late night"
  end
end
