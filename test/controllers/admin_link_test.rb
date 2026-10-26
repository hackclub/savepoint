require "test_helper"

# The Admin link in the account menu (shared/_top_bar).
class AdminLinkTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "an admin's account menu links to the admin pages" do
    sign_in_as(users(:orpheus))
    get shop_path

    assert_select "#top-bar-account a.top-bar__admin[href=?]", admin_root_path, text: /Admin/
  end

  test "a participant's account menu has no admin link" do
    sign_in_as(users(:ana))
    get shop_path

    assert_select "#top-bar-account"
    assert_select "a[href=?]", admin_root_path, 0
  end

  test "while an admin views as someone else the link is gone, because the admin pages would not open" do
    sign_in_as(users(:orpheus))
    post admin_user_impersonation_path(users(:ana))
    get shop_path

    assert_select "#top-bar-account"
    assert_select "a[href=?]", admin_root_path, 0
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
