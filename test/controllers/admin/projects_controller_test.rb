require "test_helper"

class Admin::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @ana = projects(:ana)
    @ana.user.update!(hackatime_uid: "2002", hackatime_access_token: "token-ana")
    @ana.update!(hackatime_projects: [ "pong" ], repo_url: "https://github.com/ana/pong")
    @ana.user.streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: 2 * 3600)
    @ana.user.streak_activities.create!(activity_date: Program::DATES.begin + 1, coded_seconds: 10 * 60)
    @ana.user.update!(current_streak: 1, timezone: "Europe/Lisbon")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see every project, search them, and open one in full" do
    travel_to Time.utc(2026, 10, 25, 12)
    sign_in_as(users(:orpheus))
    get admin_projects_path

    assert_response :success
    assert_select ".pg-admin-projects__count", "2 projects"
    assert_select ".admin__nav a[aria-current=page]", "Projects"
    assert_select "tr##{dom_id(@ana)}", text: /pong.*pong.*Ana Lovelace.*ana@hackclub\.com.*pong.*2\.2.*1/m
    assert_select "tr##{dom_id(@ana)} a[href=?]", admin_project_path(@ana), "pong"
    assert_select "tr##{dom_id(projects(:orpheus))}", text: /a rhythm game.*not linked.*0.*—/m

    get admin_projects_path(q: "pixelana")
    assert_select "tr##{dom_id(@ana)}"
    assert_select "tr##{dom_id(projects(:orpheus))}", 0
    get admin_projects_path(q: "rhythm")
    assert_select "tr##{dom_id(projects(:orpheus))}"
    assert_select "tr##{dom_id(@ana)}", 0
    get admin_projects_path(q: "nobody at all")
    assert_select ".pg-admin-projects__empty", "No projects match that."

    get admin_project_path(@ana)
    assert_response :success
    assert_select "h1", "pong"
    assert_select ".leaderboard__note", /By\s+Ana Lovelace \(ana@hackclub\.com, pixelana on Slack\), signed Sep 30, in Europe\/Lisbon/m
    assert_select ".admin__tile", text: /Hours\s*2\.2\s*2\.2 of [\d.]+ hrs/m
    assert_select ".admin__tile", text: /Streak\s*1\s*2 days built/m
    assert_select ".admin__tile", text: /Ship\s*Not yet\s*can ship/m
    assert_select ".admin__ship-details", /pong.*Hackatime.*pong/m
    assert_select ".admin__ship-details a[href='https://github.com/ana/pong']"
    assert_select ".admin__table--days tr", text: /Oct 23\s*2\s*counts for the streak/m
    assert_select ".admin__table--days tr", text: /Oct 24\s*0\.2\s*under 20 minutes/m
    assert_select "#admin-project-ships + p", "Not shipped yet."
    assert_select "form[action=?]", admin_user_impersonation_path(@ana.user)
  end

  test "a project's buddy and ships link through" do
    sign_in_as(users(:orpheus))
    @ana.pair_with(projects(:orpheus))
    ship = @ana.ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                              repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", hours: 2.2,
                              screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)

    get admin_project_path(@ana)
    assert_select ".admin__ship-details a[href=?]", admin_project_path(projects(:orpheus)), "a rhythm game"
    assert_select ".admin__tile a[href=?]", admin_ship_path(ship), "In review"
    assert_select "#admin-project-ships ~ div tr##{dom_id(ship)}", /In review/

    get admin_projects_path
    assert_select "tr##{dom_id(@ana)} a[href=?]", admin_ship_path(ship), "In review"
    assert_select "tr##{dom_id(@ana)} a[href=?]", admin_project_path(projects(:orpheus)), "a rhythm game"

    get admin_ship_path(ship)
    assert_select ".admin__tile a[href=?]", admin_project_path(@ana), "pong"
  end

  test "nobody else can see them" do
    get admin_projects_path
    assert_response :not_found
    get admin_project_path(@ana)
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_projects_path
    assert_response :not_found
    get admin_project_path(@ana)
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
