require "test_helper"

class NpsResponsesControllerTest < ActionDispatch::IntegrationTest
  setup { NpsResponse.asking = true }

  test "signed out goes home" do
    get nps_path
    assert_redirected_to root_path
  end

  test "the form has the score and the three questions" do
    sign_in_as(users(:orpheus))
    get nps_path
    assert_response :success
    assert_select "input[type=radio][name='nps_response[score]']", 11
    assert_select "textarea[name='nps_response[doing_well]'][required]"
    assert_select "textarea[name='nps_response[improve]'][required]"
    assert_select "textarea[name='nps_response[anything_else]']:not([required])"
  end

  test "an answer is saved as daily, and an incomplete one is not" do
    sign_in_as(users(:orpheus))
    assert_difference -> { NpsResponse.count }, 1 do
      post nps_path, params: { nps_response: { score: 9, doing_well: "Streaks", improve: "Prizes", anything_else: "" } }
    end
    assert_redirected_to nps_path
    response = NpsResponse.last
    assert_equal [ "daily", 9, nil ], [ response.source, response.score, response.project ]

    assert_no_difference -> { NpsResponse.count } do
      post nps_path, params: { nps_response: { score: 9, doing_well: "", improve: "Prizes" } }
    end
    assert_response :unprocessable_entity
  end

  test "an answer from the ship page is a ship answer and goes back to the ship" do
    sign_in_as(users(:orpheus))
    post nps_path, params: { ship: 1, nps_response: { score: 7, doing_well: "a", improve: "b" } }
    assert_redirected_to project_ship_path
    assert_equal [ "ship", users(:orpheus).project ], NpsResponse.last.then { [ it.source, it.project ] }
  end

  test "the popup's answer goes back to the project page" do
    sign_in_as(users(:orpheus))
    post nps_path, params: { back: "project", nps_response: { score: 7, doing_well: "a", improve: "b" } }
    assert_redirected_to project_path
  end

  test "someone on the list of admins is sent away" do
    admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    sign_in_as(users(:orpheus))
    get nps_path
    assert_redirected_to root_path
  ensure
    Rails.configuration.x.admin_slack_ids = admins
  end

  test "the project page carries the popup only when it is due and there is Hackatime time" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(users(:orpheus))
    get project_path
    assert_select ".nps-popup", 0

    users(:orpheus).streak_activities.create!(activity_date: Date.new(2026, 10, 1), coded_seconds: 600)
    get project_path
    assert_select ".nps-popup dialog form[action=?]", nps_path

    NpsResponse.create!(user: users(:orpheus), source: "daily", score: 8, doing_well: "a", improve: "b")
    get project_path
    assert_select ".nps-popup", 0
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id)
      post "/auth/hackclub"
      follow_redirect!
    end
end
