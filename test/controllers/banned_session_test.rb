require "test_helper"

# D-113: a ban ends the sessions already open, on the person's next request. (Signing in as a banned account is D-063:
# SessionsControllerTest.)
class BannedSessionTest < ActionDispatch::IntegrationTest
  # The project page depends on the program calendar, so the clock stays inside the program, as in ShipsControllerTest.
  setup do
    travel_to Time.utc(2026, 10, 28, 12)
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ users(:orpheus).slack_id ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "a banned account's open session ends on its next request, with the sign-in refusal" do
    sign_in_as(users(:ana))
    get project_path
    assert_response :success
    assert_equal users(:ana).id, session[:user_id]

    users(:ana).ban!("Fraud.", by: users(:orpheus))
    get project_path

    assert_redirected_to root_path
    assert_nil session[:user_id]
    assert_equal "This account can't sign in to Save Point.", flash[:alert]
  end

  test "they land on the signed-out home page, and nothing loops" do
    sign_in_as(users(:ana))
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    get root_path # where a signed-in person is sent on to their project
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_select "h1", /Finish that game you started/
    assert_nil session[:user_id]

    get root_path
    assert_response :success
    get project_path
    assert_redirected_to onboarding_path # as for anyone signed out
  end

  test "a change they ask for isn't made: the session ends instead" do
    sign_in_as(users(:ana))
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    patch project_path, params: { project: { prize_key: "k2" } }

    assert_redirected_to root_path
    assert_nil session[:user_id]
    assert_equal "u2c", projects(:ana).reload.prize_key
  end

  test "their request writes nothing for them before it ends: no timezone, no visit, no last seen" do
    users(:ana).update!(timezone: "America/New_York")
    sign_in_as(users(:ana))
    get project_path
    users(:ana).ban!("Fraud.", by: users(:orpheus))
    travel 5.minutes # long enough for the last seen to be written again, if anything wrote it
    cookies[:timezone] = "Europe/Berlin"

    assert_no_difference -> { Visit.count } do
      assert_no_changes -> { users(:ana).reload.slice(:timezone, :last_seen_at) } do
        get project_path
      end
    end
    assert_redirected_to root_path
  end

  test "a fetch for JSON gets a 401 with the refusal, and the session is gone" do
    sign_in_as(users(:ana))
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    get hours_project_path, as: :json

    assert_response :unauthorized
    assert_equal ApplicationController::BANNED_ALERT, response.parsed_body["error"]
    assert_nil session[:user_id]
    assert_equal ApplicationController::BANNED_ALERT, flash[:alert] # for the next page they open
  end

  test "someone who isn't banned is left alone, whoever else is" do
    sign_in_as(users(:orpheus))
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    get project_path
    assert_response :success
    get leaderboard_path
    assert_response :success
    assert_equal users(:orpheus).id, session[:user_id]
    assert_nil flash[:alert]
  end

  test "an admin viewing as a banned person still sees the site, and can stop" do
    sign_in_as(users(:orpheus))
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    post admin_user_impersonation_path(users(:ana))
    assert_redirected_to project_path
    get project_path
    assert_response :success
    assert_select ".impersonation", text: /Viewing as Ana Lovelace.*you're Orpheus/m
    assert_equal [ users(:ana).id, users(:orpheus).id ], [ session[:user_id], session[:impersonator_id] ]

    get leaderboard_path
    assert_response :success
    assert_nil flash[:alert]

    delete admin_impersonation_path
    assert_redirected_to admin_users_path
    assert_equal users(:orpheus).id, session[:user_id]
    assert_nil session[:impersonator_id]
  end

  test "a browser still holding a banned session can sign in as someone else" do
    sign_in_as(users(:ana))
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    sign_in_as(users(:orpheus))

    assert_equal users(:orpheus).id, session[:user_id]
    get project_path
    assert_response :success
  end

  test "a banned person signing in again is refused, and the session they still hold ends with no loop" do
    sign_in_as(users(:ana))
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    sign_in_as(users(:ana))
    assert_redirected_to root_path # SessionsController#create refuses them
    assert_equal ApplicationController::BANNED_ALERT, flash[:alert]

    follow_redirect!
    assert_redirected_to root_path # and the session they held ends here
    follow_redirect!
    assert_response :success
    assert_nil session[:user_id]
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
