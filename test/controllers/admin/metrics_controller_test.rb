require "test_helper"

class Admin::MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    MetricSnapshot.create!(day: Date.new(2026, 10, 23), key: "signed_in", value: 10)
    MetricSnapshot.create!(day: Date.new(2026, 10, 24), key: "signed_in", value: 14)
    MetricSnapshot.create!(day: Date.new(2026, 10, 24), key: "hours_day", value: 2.5)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see each number by day, with the day's change on totals" do
    travel_to Time.utc(2026, 10, 25, 12)
    sign_in_as(users(:orpheus))
    get admin_metrics_path

    assert_response :success
    assert_select "thead th", text: "Oct 23"
    assert_select "tr", text: /Signed in\s*10\s*14\s*\+4/
    assert_select "tr", text: /Hours that day\s*—\s*2\.5/
  end

  test "a fractional change is rounded to one decimal" do
    MetricSnapshot.create!(day: Date.new(2026, 10, 23), key: "hours", value: 300.1)
    MetricSnapshot.create!(day: Date.new(2026, 10, 24), key: "hours", value: 323.4)
    sign_in_as(users(:orpheus))
    get admin_metrics_path

    assert_select "small.am__change", text: "+23.3"
    assert_select "small.am__change", text: /\d{3,}\.\d{2,}/, count: 0
  end

  test "the NPS of the last 7 days and the latest written answers" do
    travel_to Time.utc(2026, 10, 25, 12)
    NpsResponse.create!(user: users(:ana), source: "daily", score: 10, doing_well: "Loved the streaks", improve: "More prizes")
    sign_in_as(users(:orpheus))
    get admin_metrics_path

    assert_select ".am__nps-big", "+100"
    assert_select ".am__nps-card .am__nps-text", text: "Loved the streaks"
    assert_select ".am__nps-card .am__nps-text", text: "More prizes"
    assert_select ".am__nps-card .am__nps-qa dt", text: "What are we doing well?"
    assert_select ".am__nps-card .am__nps-qa dt", text: "Anything else you want to tell us?", count: 0
  end

  test "with no NPS answers it says so" do
    sign_in_as(users(:orpheus))
    get admin_metrics_path
    assert_select ".am__nps .am__note", text: /Nobody has answered yet/
  end

  test "nobody else can see it" do
    get admin_metrics_path
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id)
      post "/auth/hackclub"
      follow_redirect!
    end

  test "where sign-ups come from: visits and sign-ups per tag, and the untagged, without admins" do
    users(:ana).update!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch")
    users(:orpheus).update!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch")
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    3.times { Visit.create!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch", path: "/") }
    Visit.create!(utm_source: "twitter", path: "/")
    2.times { Visit.create!(path: "/") }
    Visit.create!(path: "/project")
    sign_in_as(users(:orpheus))
    get admin_metrics_path

    assert_select "h2", text: "Where sign-ups come from"
    assert_select "tr", text: /slack\s*post\s*launch\s*3\s*1\s*33%/
    assert_select "tr", text: /twitter\s*—\s*—\s*1\s*0\s*0%/
    untagged = User.participants.where(utm_source: nil).count
    assert_select "tr", text: /No tags\s*2\s*#{untagged}\s*#{(100.0 * untagged / 2).round}%/
    assert_select "tr", text: /\A\s*—\s*—\s*—/, count: 0 # no all-nil row
  end
end
