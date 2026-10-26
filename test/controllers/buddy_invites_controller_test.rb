require "test_helper"

class BuddyInvitesControllerTest < ActionDispatch::IntegrationTest
  test "anyone can see who's inviting them and what they'd both get" do
    get buddy_invite_path("k3j9x2qa")

    assert_response :success
    assert_select ".buddy-invited__title", "pixelana invited you to build together."
    assert_no_match(/Ana|Lovelace/, response.body, "never their real name")
    assert_select ".buddy-card__title", "pong"
    assert_select ".buddy-invited__reward", count: 0
    assert_no_match(/Kartikey|handheld|small rewards/, response.body)
    assert_select "button", "Pair up"
  end

  test "a link that doesn't exist says so" do
    get buddy_invite_path("nobody")
    assert_response :not_found
    assert_select "h1", "This invite link isn't valid."
  end

  test "accepting pairs you up" do
    sign_in_as_orpheus
    post buddy_invite_path("k3j9x2qa")

    assert_redirected_to buddy_path
    assert_equal projects(:ana), projects(:orpheus).reload.buddy
    assert_equal projects(:orpheus), projects(:ana).reload.buddy
    follow_redirect!
    assert_select "h1", "You + pixelana"
    assert_select ".pg-buddies__buddy", /pixelana/
    assert_select "[aria-label='1 buddy']", "1"

    get buddy_invite_path("k3j9x2qa")
    assert_select ".project__step-error", "You already have a buddy."
    assert_select "button", text: "Pair up", count: 0
  end

  test "without a project yet, accepting waits until you've signed your pledge" do
    mock_hack_club_auth
    post "/auth/hackclub"
    follow_redirect!
    post buddy_invite_path("k3j9x2qa")
    assert_redirected_to onboarding_path

    post project_path, as: :json, params: { project: { name: "A mail RPG", prize_key: "u2c" } }
    assert_equal buddy_path, response.parsed_body["location"]
    assert_equal projects(:ana), User.find_by!(hca_id: "ident!heidi").project.buddy
  end

  test "accepting before signing in still pairs you once you've signed your pledge" do
    post buddy_invite_path("k3j9x2qa")
    assert_redirected_to onboarding_path

    mock_hack_club_auth
    post "/auth/hackclub"
    follow_redirect!

    post project_path, as: :json, params: { project: { name: "A mail RPG", prize_key: "u2c" } }
    assert_equal buddy_path, response.parsed_body["location"]
    assert_equal projects(:ana), User.find_by!(hca_id: "ident!heidi").project.buddy
  end

  test "your own link is yours" do
    mock_hack_club_auth(uid: users(:ana).hca_id, slack_id: "U0ANA")
    post "/auth/hackclub"
    follow_redirect!
    get buddy_invite_path("k3j9x2qa")

    assert_select ".buddy-invited__title", "This is your own invite link."
    assert_select "button", text: "Pair up", count: 0
  end

  private
    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end
end
