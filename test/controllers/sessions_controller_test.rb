require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { mock_hack_club_auth }

  test "signing in with Hack Club Auth creates the user and returns to where they started" do
    assert_difference -> { User.count } do
      post "/auth/hackclub", params: { origin: onboarding_path }
      follow_redirect!
    end

    assert_redirected_to onboarding_path
    assert_equal User.find_by!(hca_id: "ident!heidi").id, session[:user_id]
  end

  test "a banned account can't sign in (D-063)" do
    User.create!(hca_id: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi", slack_id: "U0HEIDI",
                 banned_at: Time.current, ban_reason: "Fraud.")
    post "/auth/hackclub"
    follow_redirect!
    assert_redirected_to root_path
    assert_nil session[:user_id]
    assert_equal "This account can't sign in to Save Point.", flash[:alert]
  end

  test "signing in adds you to the Slack channels, until you've been added" do
    post "/auth/hackclub"
    assert_enqueued_with(job: JoinSlackChannelsJob) { follow_redirect! }

    User.find_by!(hca_id: "ident!heidi").update!(slack_channels_joined_at: Time.current)
    post "/auth/hackclub"
    assert_no_enqueued_jobs(only: JoinSlackChannelsJob) { follow_redirect! }
  end

  test "signing in remembers your browser's timezone" do
    cookies[:timezone] = "Europe/Berlin"
    post "/auth/hackclub"
    follow_redirect!

    assert_equal "Europe/Berlin", User.find_by!(hca_id: "ident!heidi").timezone
  end

  test "signing in looks up your Slack profile, for your display name (and timezone, if your browser hasn't said)" do
    post "/auth/hackclub"
    assert_enqueued_with(job: SlackProfileJob) { follow_redirect! }
  end

  test "a signed-in browser in a new timezone moves you there" do
    post "/auth/hackclub"
    follow_redirect!
    cookies[:timezone] = "Asia/Tokyo"
    get root_path

    assert_equal "Asia/Tokyo", User.find_by!(hca_id: "ident!heidi").timezone
  end

  test "won't return anywhere off the site" do
    post "/auth/hackclub", params: { origin: "https://evil.example/phish" }
    follow_redirect!

    assert_redirected_to "/phish"
  end

  test "a failed sign-in goes back to onboarding with the reason" do
    get auth_failure_path, params: { message: "access_denied" }

    assert_redirected_to onboarding_path
    assert_equal "Couldn't sign you in with Hack Club (access denied).", flash[:alert]
  end

  # D-026: sign-in chains on to Hackatime.
  test "signing in with no Hackatime token goes on to the Hackatime step" do
    with_hackatime_app do
      post "/auth/hackclub", params: { origin: shop_path }
      follow_redirect!

      assert_redirected_to sign_in_hackatime_path
      get sign_in_hackatime_path
      assert_response :success
      assert_select "form[action='/auth/hackatime'][data-controller='auto-submit']"
      assert_select "form input[name='origin'][value='#{sign_in_hackatime_path}']"
      assert_select "form button", /Continue to Hackatime/
    end
  end

  test "signing in with a Hackatime token keeps the old redirect" do
    link_hackatime(users(:orpheus))
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    with_hackatime_app do
      post "/auth/hackclub", params: { origin: shop_path }
      follow_redirect!

      assert_redirected_to shop_path
    end
  end

  test "signing in without our own Hackatime app keeps the old redirect" do
    post "/auth/hackclub", params: { origin: shop_path }
    follow_redirect!

    assert_redirected_to shop_path
  end

  test "signing in with a Hackatime client id but the chain switch off keeps the old redirect" do
    Rails.configuration.x.hackatime_configured = true
    begin
      post "/auth/hackclub", params: { origin: shop_path }
      follow_redirect!

      assert_redirected_to shop_path
    ensure
      Rails.configuration.x.hackatime_configured = false
    end
  end

  test "the Hackatime step without the flag goes to onboarding" do
    with_hackatime_app do
      get sign_in_hackatime_path
      assert_redirected_to onboarding_path

      post "/auth/hackclub"
      follow_redirect!
      get sign_in_hackatime_path
      assert_response :success
    end
  end

  test "reloading the Hackatime step goes to onboarding" do
    with_hackatime_app do
      post "/auth/hackclub"
      follow_redirect!
      get sign_in_hackatime_path
      assert_response :success

      get sign_in_hackatime_path
      assert_redirected_to onboarding_path
    end
  end

  test "the Hackatime step goes to onboarding when you're not signed in" do
    with_hackatime_app { get sign_in_hackatime_path }
    assert_redirected_to onboarding_path
  end

  test "a Hackatime failure after the step keeps you signed in and goes to onboarding" do
    with_hackatime_app do
      post "/auth/hackclub"
      follow_redirect!
      get sign_in_hackatime_path
      get auth_failure_path, params: { message: "access_denied", strategy: "hackatime" }

      assert_redirected_to onboarding_path
      assert_equal "Couldn't link Hackatime (access denied). Try again.", flash[:alert]
      assert_equal User.find_by!(hca_id: "ident!heidi").id, session[:user_id]
    end
  end

  test "logging out ends the session" do
    post "/auth/hackclub"
    follow_redirect!
    delete logout_path

    assert_redirected_to root_path
    assert_nil session[:user_id]
  end

  test "signing in keeps what Hack Club Auth shares (address, phone, birthdate), and keeps it when a sign-in doesn't" do
    users(:orpheus).update!(address: nil)
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", address: HQ_ADDRESS)
    post "/auth/hackclub"
    follow_redirect!
    assert_equal [ HQ_ADDRESS, "+18025550123", "2010-04-01" ], users(:orpheus).reload.values_at(:address, :phone_number, :birthdate)

    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", address: nil, phone_number: nil, birthdate: nil)
    post "/auth/hackclub"
    follow_redirect!
    assert_equal [ HQ_ADDRESS, "+18025550123", "2010-04-01" ], users(:orpheus).reload.values_at(:address, :phone_number, :birthdate)
  end

  test "sign-in asks Hack Club Auth for every scope it has" do
    assert_equal %i[openid profile email phone address birthdate slack_id verification_status], Rails.configuration.x.hack_club_auth_scopes
  end

  private
    def with_hackatime_app
      Rails.configuration.x.hackatime_chain = true
      yield
    ensure
      Rails.configuration.x.hackatime_chain = false
    end
end
