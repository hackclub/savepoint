require "test_helper"

class Admin::ImpersonationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0HEIDI" ]
    @heidi = User.create!(hca_id: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi", slack_id: "U0HEIDI")
    @newcomer = User.create!(hca_id: "ident!newcomer", email: "new@hackclub.com", name: "Nova Newcomer", first_name: "Nova")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "an admin sees the site as someone, then gets their own session back" do
    sign_in_as(users(:orpheus))

    post admin_user_impersonation_path(users(:ana))
    assert_redirected_to project_path # Ana's pledged, so her project
    assert_equal users(:ana).id, session[:user_id]
    assert_equal users(:orpheus).id, session[:impersonator_id]

    get project_path
    assert_response :success
    assert_select ".impersonation", text: /Viewing as Ana Lovelace.*you're Orpheus/m
    assert_select ".impersonation form[action=?]", admin_impersonation_path

    get admin_users_path
    assert_response :not_found # Ana isn't an admin, so neither is the site right now

    delete admin_impersonation_path
    assert_redirected_to admin_users_path
    assert_equal users(:orpheus).id, session[:user_id]
    assert_nil session[:impersonator_id]

    get admin_users_path
    assert_response :success
    assert_select ".impersonation", 0
  end

  test "viewing as someone who hasn't pledged lands on onboarding" do
    sign_in_as(users(:orpheus))

    post admin_user_impersonation_path(@newcomer)
    assert_redirected_to onboarding_path
  end

  test "the admin's browser timezone doesn't become theirs" do
    users(:ana).update!(timezone: "Europe/Berlin")
    sign_in_as(users(:orpheus))
    post admin_user_impersonation_path(users(:ana))

    cookies[:timezone] = "America/New_York"
    get project_path
    assert_equal "Europe/Berlin", users(:ana).reload.timezone
  end

  test "not yourself, not another admin" do
    sign_in_as(users(:orpheus))

    post admin_user_impersonation_path(users(:orpheus))
    assert_redirected_to admin_users_path
    assert_nil session[:impersonator_id]

    post admin_user_impersonation_path(@heidi)
    assert_redirected_to admin_users_path
    assert_nil session[:impersonator_id]
  end

  test "nobody else can start one, and stopping without one goes home" do
    post admin_user_impersonation_path(users(:ana))
    assert_response :not_found

    sign_in_as(users(:ana))
    post admin_user_impersonation_path(@heidi)
    assert_response :not_found

    delete admin_impersonation_path
    assert_redirected_to root_path
    assert_equal users(:ana).id, session[:user_id]
  end

  test "viewing as someone is read-only: nothing they could change gets changed" do
    sign_in_as(users(:orpheus))
    post admin_user_impersonation_path(users(:ana))

    patch project_path, params: { project: { prize_key: "k2" } }
    assert_redirected_to project_path
    assert_match(/Stop viewing as them/, flash[:alert])
    assert_equal "u2c", projects(:ana).reload.prize_key

    assert_no_difference -> { Order.count } do
      post shop_order_path, params: { order: { prize_key: "micro" } }
    end
    assert_match(/Stop viewing as them/, flash[:alert])

    patch project_path, params: { project: { prize_key: "k2" } }, as: :json
    assert_response :forbidden
    assert_match(/viewing as/i, response.parsed_body["error"])
    assert_equal "u2c", projects(:ana).reload.prize_key

    get project_path
    assert_response :success
  end

  test "viewing as someone can still be stopped, and the admin can still sign out" do
    sign_in_as(users(:orpheus))
    post admin_user_impersonation_path(users(:ana))
    delete admin_impersonation_path
    assert_redirected_to admin_users_path
    assert_equal users(:orpheus).id, session[:user_id]
    assert_nil session[:impersonator_id]

    post admin_user_impersonation_path(users(:ana))
    delete logout_path
    assert_redirected_to root_path
    assert_nil session[:user_id]
    assert_nil session[:impersonator_id]
  end

  test "the Hackatime callback doesn't relink the person being viewed" do
    link_hackatime(users(:ana), token: "token-heidi")
    sign_in_as(users(:orpheus))
    post admin_user_impersonation_path(users(:ana))
    mock_hackatime(token: "token-orpheus")

    assert_no_changes -> { users(:ana).reload.slice(:hackatime_uid, :hackatime_access_token) } do
      post "/auth/hackatime"
      follow_redirect!
    end
    assert_redirected_to project_path
    assert_match(/Stop viewing as them/, flash[:alert])
  end

  test "starting and stopping a view are written to the admin log" do
    sign_in_as(users(:orpheus))

    assert_difference -> { AdminAuditEvent.count }, 1 do
      post admin_user_impersonation_path(users(:ana))
    end
    started = AdminAuditEvent.newest.first
    assert_equal [ "impersonate", users(:orpheus), { "user_id" => users(:ana).id }, nil ],
                 [ started.tool, started.user, started.ids, started.admin_token ]

    assert_difference -> { AdminAuditEvent.count }, 1 do
      delete admin_impersonation_path
    end
    stopped = AdminAuditEvent.newest.first
    assert_equal [ "stop_impersonating", users(:orpheus), { "user_id" => users(:ana).id } ], [ stopped.tool, stopped.user, stopped.ids ]
  end

  test "a refused view-as writes nothing to the admin log" do
    sign_in_as(users(:orpheus))
    assert_no_difference -> { AdminAuditEvent.count } do
      post admin_user_impersonation_path(@heidi)
    end
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
