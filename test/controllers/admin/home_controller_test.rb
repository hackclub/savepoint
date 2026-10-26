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
    assert_equal %w[Admin Orders Ships Extensions Projects People Bandit Tokens Insights], css_select(".admin__nav a").map(&:text)
    assert_select ".pg-admin-home__total", /1\s*waiting/
    assert_select "a.admin__tile[href=?][data-waiting]", admin_extensions_path, /Extensions\s*1\s*waiting/
    assert_select "a.admin__tile[href=?]:not([data-waiting])", admin_ships_path, /Ships\s*0\s*in review/
    assert_select ".admin__table--pages tbody tr", 8
    assert_select ".admin__table--pages tr", text: /Projects.*Every project, searchable.*#{Project.count}/m

    assert_select ".admin__table--pages th a", text: /Stats|Numbers/, count: 0
    assert_select ".admin__nav a", text: /Stats|Numbers/, count: 0

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
    assert_select "svg.admin-chart__columns[role=img]", 6
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

  test "the NPS of the last 7 days is on the home page, without admins" do
    NpsResponse.create!(user: users(:ana), source: "daily", score: 10, doing_well: "Streaks", improve: "Prizes")
    NpsResponse.create!(user: users(:orpheus), source: "daily", score: 0, doing_well: "Nothing", improve: "Everything")
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_select ".admin-chart--split", text: /NPS/ do
      assert_select ".admin-chart__takeaway", /\+100 NPS from 1 person/
      assert_select ".admin-chart__legend tbody tr", text: /Promoters.*1.*100%/m
      assert_select ".admin-chart__legend tbody tr", text: /Detractors.*0/m
    end
    assert_select ".admin-chart a", 0
    assert_select "#signups .admin-chart--split", 1, "one NPS section, not two"
  end

  test "with no NPS answers the home page says so" do
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_response :success
    assert_select ".admin-chart__takeaway", "Nobody has answered in the last 7 days."
    assert_select ".admin-chart__legend tbody tr", text: /Promoters.*0/m
  end

  test "every number is in one page: a section for each, with jump links to them" do
    sign_in_as(users(:orpheus))
    get admin_root_path

    ids = %w[waiting building funnel stuck prizes signups growth history]
    ids.each do |id|
      assert_select "main section##{id}", 1
      assert_select ".pg-admin-home__jump a[href=?]", "##{id}"
    end
    assert_select "#waiting .admin__tile", 3, "the waiting block is whole"
    %w[growth signups history stuck].each do |frame|
      assert_select "turbo-frame#admin-#{frame}[loading=lazy][src=?]", send("admin_#{frame}_path")
    end
  end

  test "DAU shows how many of today's builders also opened the site, and a dash before it was recorded" do
    sign_in_as(users(:orpheus))
    travel_to Program::DATES.begin + 4
    get admin_root_path
    assert_select ".admin__readout", text: /DAU.*site visits: –/m

    users(:ana).streak_activities.create!(activity_date: Program::DATES.begin + 4, coded_seconds: 30 * 60)
    CodedBucket.create!(user: users(:ana), bucket_at: CodedBucket.floor(1.hour.ago), seconds: 600)
    SiteDay.create!(user: users(:ana), date: Program::DATES.begin + 4)
    Rails.cache.clear
    get admin_root_path
    assert_select ".admin__readout", text: /DAU.*1 also opened the site/m
    assert_select ".admin-chart", text: /Also on the site/
  end

  test "the DAU tile says built in the last 24 hours, and the charts end on a partial column for today with the averages on finished days" do
    sign_in_as(users(:orpheus))
    travel_to Program::DATES.begin + 4
    users(:ana).streak_activities.create!(activity_date: Program::DATES.begin + 3, coded_seconds: 3600)
    users(:ana).streak_activities.create!(activity_date: Program::DATES.begin + 4, coded_seconds: 120)
    CodedBucket.create!(user: users(:ana), bucket_at: CodedBucket.floor(1.hour.ago), seconds: 120)
    get admin_root_path

    assert_select ".admin__readout", text: /DAU\s*1\s*built in the last 24 hours\s*plus 0 unconfirmed/
    assert_select ".pg-admin-home__sub", text: /today so far, then finished days/
    assert_select ".admin-chart--daily .admin-chart__day.is-partial", 5, "one for each of the five charts"
    assert_select ".admin-chart--daily .admin-chart__axis span:last-child", text: "Today", minimum: 5
    assert_select ".admin-chart__day.is-partial title", text: /today so far/, minimum: 5
    assert_select ".admin-chart--daily", text: /Hours built.*1\.0\s*h in #{(Date.current - Program::HACKATIME_START).to_i} finished days/m
  end

  test "with site visits recorded only today, the site card shows today's partial bar and says so" do
    sign_in_as(users(:orpheus))
    travel_to Program::DATES.begin + 4
    users(:ana).streak_activities.create!(activity_date: Date.current, coded_seconds: 600)
    CodedBucket.create!(user: users(:ana), bucket_at: CodedBucket.floor(1.hour.ago), seconds: 600)
    SiteDay.create!(user: users(:ana), date: Date.current)
    get admin_root_path

    assert_select ".admin-chart--daily", text: /Also on the site.*Today so far: 1 of 1 builder also opened the site/m
    assert_select ".admin-chart--daily", text: /Not recorded yet/, count: 0
    assert_select ".admin__readout", text: /DAU.*1 also opened the site/m
    assert_select ".admin-chart--daily:has(.admin__readout-name):has(.admin-chart__day.is-partial .admin-chart__column)", minimum: 1
  end

  test "the sign-up day card reports today so far when only today has sign-ups" do
    sign_in_as(users(:orpheus))
    travel_to Program::DATES.begin + 4
    User.where.not(slack_id: "U0ORPHEUS").update_all(created_at: Program::DATES.begin - 5)
    ana = users(:ana)
    ana.update_columns(created_at: Time.current)
    ana.streak_activities.create!(activity_date: Date.current, coded_seconds: 25 * 60)
    get admin_root_path

    assert_select ".admin-chart--daily", text: /Built on their sign-up day.*Today so far: 1 of 1 sign-up built 20 minutes/m
  end

  test "the old Stats and Numbers pages go to their sections of the home page" do
    sign_in_as(users(:orpheus))

    get "/admin/stats"
    assert_redirected_to "/admin#growth"
    assert_response :moved_permanently
    get "/admin/metrics"
    assert_redirected_to "/admin#history"
    assert_response :moved_permanently
  end

  test "the growth section has the totals, the simulator on the admin page and the streaks, and no second funnel" do
    sign_in_as(users(:orpheus))
    travel_to Program::DATES.begin + 4
    user = User.create!(hca_id: "ident!daily", first_name: "Daily")
    (0..2).each { |ago| user.streak_activities.create!(activity_date: Program::DATES.begin + 3 - ago, coded_seconds: 6 * 60) }
    get admin_growth_path, headers: { "Turbo-Frame" => "admin-growth" }

    assert_response :success
    assert_select "turbo-frame#admin-growth" do
      assert_select ".admin__readout-name", text: /Builders/
      assert_select ".admin__readout-name", text: /Games shipped/
      assert_select ".admin__readout-name", text: /CURR/
      assert_select "body", text: /WAU|MAU|weekly|monthly/i, count: 0
      assert_select ".stats__lines", minimum: 2
      assert_select ".stats__toggle a[href^=?]", admin_growth_path, minimum: 2
      assert_select ".stats__toggle a[href*=?]", "signups=flat"
      assert_select ".stats__levers, .admin__table--wide th", text: /Rate/
      assert_select ".admin__readout-name", text: /On a streak/
      assert_select ".admin-chart__steps", 1, "only the streak bars: the funnel is on the home page"
    end
    assert_select ".admin-bar", 0, "a frame request is just the frame"

    get admin_growth_path(signups: "flat"), headers: { "Turbo-Frame" => "admin-growth" }
    assert_select ".stats__toggle-option--active", "Flat"
  end

  test "who's stuck lists people who stopped by step, linking to their admin page, and not admins" do
    sign_in_as(users(:orpheus))
    users(:ana).update_columns(last_seen_at: 2.hours.ago, last_seen_path: "/project")
    get admin_stuck_path, headers: { "Turbo-Frame" => "admin-stuck" }

    assert_select "details.admin-stuck", 5
    assert_select "details.admin-stuck[data-empty]", 4, "a group nobody is in has no table to open"
    assert_select "details.admin-stuck summary", text: /Pledged, not picked\s*1/
    assert_select "tr", text: /pixelana.*2 hours ago.*\/project/m
    assert_select "a.admin-person[href=?]", admin_user_path(users(:ana))
    assert_select "a.admin-person[href=?]", admin_user_path(users(:orpheus)), 0
  end

  test "opening a section's URL itself shows it under the admin bar" do
    sign_in_as(users(:orpheus))
    get admin_history_path
    assert_response :success
    assert_select ".admin-bar", 1
  end

  test "sign-ups: the latest NPS answers and where sign-ups come from, without admins" do
    NpsResponse.create!(user: users(:ana), source: "daily", score: 10, doing_well: "Loved the streaks", improve: "More prizes")
    users(:ana).update!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch")
    users(:orpheus).update!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch")
    3.times { Visit.create!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch", path: "/") }
    Visit.create!(utm_source: "twitter", path: "/")
    2.times { Visit.create!(path: "/") }
    Visit.create!(path: "/project")
    sign_in_as(users(:orpheus))
    get admin_signups_path, headers: { "Turbo-Frame" => "admin-signups" }

    assert_select ".admin-answer__pill--promoter", "10"
    assert_select ".admin-answer__qa dd", "Loved the streaks"
    assert_select ".admin-answer__qa dd", "More prizes"
    assert_select ".admin-answer__qa dt", text: "Anything else you want to tell us?", count: 0
    assert_select "tr", text: /slack\s*post\s*launch\s*3\s*1\s*33%/
    assert_select "tr", text: /twitter\s*—\s*—\s*1\s*0\s*0%/
    untagged = User.participants.where(utm_source: nil).count
    assert_select "tr", text: /No tags\s*2\s*#{untagged}\s*#{(100.0 * untagged / 2).round}%/
  end

  test "with no NPS answers the sign-ups section says so" do
    sign_in_as(users(:orpheus))
    get admin_signups_path, headers: { "Turbo-Frame" => "admin-signups" }
    assert_select ".admin-chart__empty", text: /Nobody has answered yet/
  end

  test "history: each number by day, with the day's change on totals" do
    MetricSnapshot.create!(day: Date.new(2026, 10, 23), key: "signed_in", value: 10)
    MetricSnapshot.create!(day: Date.new(2026, 10, 24), key: "signed_in", value: 14)
    MetricSnapshot.create!(day: Date.new(2026, 10, 24), key: "hours_day", value: 2.5)
    MetricSnapshot.create!(day: Date.new(2026, 10, 23), key: "hours", value: 300.1)
    MetricSnapshot.create!(day: Date.new(2026, 10, 24), key: "hours", value: 323.4)
    travel_to Time.utc(2026, 10, 25, 12)
    sign_in_as(users(:orpheus))
    get admin_history_path, headers: { "Turbo-Frame" => "admin-history" }

    assert_select "thead th", text: "Oct 23"
    assert_select "tr", text: /Signed in\s*10\s*14\s*\+4/
    assert_select "tr", text: /Hours that day\s*—\s*2\.5/
    assert_select "small.admin__change", text: "+23.3"
    assert_select "small.admin__change", text: /\d{3,}\.\d{2,}/, count: 0
  end

  test "the new sections are for admins only" do
    %w[growth signups history stuck].each do |section|
      get "/admin/#{section}"
      assert_response :not_found
    end
    sign_in_as(users(:ana))
    %w[growth signups history stuck].each do |section|
      get "/admin/#{section}"
      assert_response :not_found
    end
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
