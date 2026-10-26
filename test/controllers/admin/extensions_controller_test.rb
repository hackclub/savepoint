require "test_helper"

class Admin::ExtensionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @extension = projects(:ana).create_extension!(reason: "exams until the 22nd")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see who's waiting, and approve or deny" do
    sign_in_as(users(:orpheus))
    get admin_extensions_path

    assert_response :success
    assert_select ".pg-admin-extensions__count", /1 waiting/
    assert_select ".admin__nav a[aria-current=page]", "Extensions"
    assert_select "tr##{dom_id(@extension)}", text: /Ana Lovelace.*pong.*exams until the 22nd/m
    assert_select "tr##{dom_id(@extension)} form[action=?]", admin_extension_path(@extension), 2

    patch admin_extension_path(@extension), params: { decision: "approved" }
    assert_redirected_to admin_extensions_path
    assert @extension.reload.approved?
    assert_equal users(:orpheus), @extension.decided_by
    assert_equal Date.new(2026, 11, 2), projects(:ana).reload.deadline
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_match(/7 more days! \*pong\* is due Nov 2 now/, dm[:args].second)

    follow_redirect!
    assert_select ".pg-admin-extensions__count", /0 waiting/
    assert_select "tr##{dom_id(@extension)} [data-decision=approved]", /Approved/
    assert_select "tr##{dom_id(@extension)} form", 0

    patch admin_extension_path(@extension), params: { decision: "denied" }
    assert_redirected_to admin_extensions_path
    assert @extension.reload.approved?, "the first decision stands"
    assert_equal "That one's been decided already.", flash[:alert]
  end

  test "denying leaves the deadline where it was" do
    sign_in_as(users(:orpheus))
    patch admin_extension_path(@extension), params: { decision: "denied" }
    assert @extension.reload.denied?
    assert_equal Date.new(2026, 11, 2), projects(:ana).reload.deadline
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_match(/still due Nov 2/, dm[:args].second)
  end

  test "nobody else can see it, or decide" do
    get admin_extensions_path
    assert_response :not_found
    patch admin_extension_path(@extension), params: { decision: "approved" }
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_extensions_path
    assert_response :not_found
    patch admin_extension_path(@extension), params: { decision: "approved" }
    assert_response :not_found
    assert @extension.reload.pending?
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
