require "test_helper"

class Admin::StatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see the stats under the admin nav, not the participant top bar" do
    sign_in_as(users(:orpheus))
    get admin_stats_path

    assert_response :success
    assert_equal "/admin/stats", admin_stats_path
    assert_select "h1", "Save Point in numbers"
    assert_select ".stats__tile", text: /Builders\s*2/
    assert_select ".admin-bar", 1
    assert_select ".admin__nav a[aria-current=page]", count: 1
    assert_select ".admin__nav a[aria-current=page][href=?]", admin_stats_path, "Stats"
    assert_select ".top-bar", 0
  end

  test "the signups toggle stays on the admin page" do
    sign_in_as(users(:orpheus))
    build_some_days
    travel_to Program::DATES.begin + 4

    get admin_stats_path
    assert_select ".stats__toggle a[href^=?]", admin_stats_path, minimum: 2
    assert_select ".stats__toggle a[href*=?]", "signups=flat"
    assert_select ".stats__toggle a[href^=?]", stats_path, 0

    get admin_stats_path(signups: "flat")
    assert_select ".stats__toggle-option--active", "Flat"
  end

  test "the public stats page keeps the participant top bar and its own toggle links" do
    build_some_days
    travel_to Program::DATES.begin + 4

    get stats_path

    assert_select ".top-bar"
    assert_select ".admin-bar", 0
    assert_select ".stats__toggle a[href^=?]", stats_path, minimum: 2
  end

  test "nobody else can see it" do
    get admin_stats_path
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_stats_path
    assert_response :not_found
  end

  private
    # The toggle is shown once someone has built (Growth).
    def build_some_days
      user = User.create!(hca_id: "ident!daily", first_name: "Daily")
      (0..2).each { |ago| user.streak_activities.create!(activity_date: Program::DATES.begin + 3 - ago, coded_seconds: 6 * 60) }
    end

    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id)
      post "/auth/hackclub"
      follow_redirect!
    end
end
