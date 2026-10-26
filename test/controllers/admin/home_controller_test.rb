require "test_helper"
require_relative "../../support/admin_mcp_helpers"

class Admin::HomeControllerTest < ActionDispatch::IntegrationTest
  include AdminMcpHelpers

  setup do
    create_insights_views
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see what's waiting on them, and every admin page with what it's for" do
    projects(:ana).create_extension!(reason: "exams")
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_response :success
    assert_equal "/admin", admin_root_path
    assert_select ".admin__nav a[aria-current=page]", "Admin"
    assert_equal %w[Admin Orders Ships Extensions Projects People Numbers Stats Bandit Tokens Insights], css_select(".admin__nav a").map(&:text)
    assert_select ".pg-admin-home__total", /1\s*waiting/
    assert_select "a.admin__tile[href=?][data-waiting]", admin_extensions_path, /Extensions\s*1\s*waiting/
    assert_select "a.admin__tile[href=?]:not([data-waiting])", admin_ships_path, /Ships\s*0\s*in review/
    assert_select ".admin__table--pages tbody tr", 10
    assert_select ".admin__table--pages tr", text: /Projects.*Every project, searchable.*#{Project.count}/m

    assert_select ".admin__table--pages th a[href=?]", admin_stats_path, "Stats"
    assert_select ".admin__nav a[href=?]:not([data-turbo=false])", admin_stats_path, "Stats"

    # And it's in the nav on every admin page.
    get admin_ships_path
    assert_select ".admin__nav a[href=?]", admin_root_path, "Admin"
    # Insights is the analytics service, not a Rails route (D-040): a plain path, a full page load, never the current page.
    assert_select ".admin__nav a[href='/admin/insights/'][data-turbo=false]", "Insights"
    assert_select ".admin__nav a[aria-current=page]", count: 1
  end

  test "admins see sign-ups, DAU and the hours funnel, without admins in them" do
    users(:ana).streak_activities.create!(activity_date: Program::HACKATIME_START, coded_seconds: 90 * 60)
    users(:orpheus).streak_activities.create!(activity_date: Program::HACKATIME_START, coded_seconds: 5 * 3600)
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_select "#admin-home-so-far"
    assert_select ".admin__readout", text: /Sign-ups\s*#{User.participants.count}/
    assert_select ".admin-chart__legend tbody tr", text: /Unapproved.*1\.5\s*h/m
    assert_select ".admin-chart__legend tbody tr", text: /Pending.*0\.0\s*h/m
    assert_select ".admin-chart__legend tbody tr", text: /Approved.*0\.0\s*h/m
    assert_select "svg.admin-chart__funnel[role=img][aria-label]"
    assert_select "svg.admin-chart__columns[role=img]", 5
  end

  test "the numbers in Save Point so far are not buttons or links" do
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_select ".pg-admin-home__readouts a, .admin-chart a", 0
    assert_select ".admin__tile", 3
    assert_select ".admin__tile--link", 3, "only the waiting tiles are tiles, and each is a link"
  end

  test "the funnel of people shows every step, a bar each, and says where the biggest drop is" do
    users(:ana).update!(hackatime_uid: "1002", hackatime_access_token: "token-ana")
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_select ".admin-chart__step", ParticipantFunnel::STEPS.size
    assert_select ".admin-chart__verdict", /Biggest drop:/
    assert_select ".admin-chart__step.is-biggest-drop", 1
    assert_select ".admin-chart__step:first-child .admin-chart__meter span[style*='width: 100.0%']"
  end

  test "the NPS of the last 7 days is on the home page, without admins, and links to Numbers" do
    NpsResponse.create!(user: users(:ana), source: "daily", score: 10, doing_well: "Streaks", improve: "Prizes")
    NpsResponse.create!(user: users(:orpheus), source: "daily", score: 0, doing_well: "Nothing", improve: "Everything")
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_select ".admin-chart--split", text: /NPS/ do
      assert_select ".admin-chart__takeaway", /\+100 NPS from 1 person/
      assert_select ".admin-chart__legend tbody tr", text: /Promoters.*1.*100%/m
      assert_select ".admin-chart__legend tbody tr", text: /Detractors.*0/m
    end
    assert_select ".pg-admin-home__sub a[href=?]", admin_metrics_path
    assert_select ".admin-chart a", 0
  end

  test "with no NPS answers the home page says so" do
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_response :success
    assert_select ".admin-chart__takeaway", "Nobody has answered in the last 7 days."
    assert_select ".admin-chart__legend tbody tr", text: /Promoters.*0/m
  end

  test "nobody else can see it" do
    get admin_root_path
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_root_path
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
