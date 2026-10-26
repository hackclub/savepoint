require "test_helper"

class LeaderboardsControllerTest < ActionDispatch::IntegrationTest
  test "without a project, it's back to onboarding" do
    get leaderboard_path
    assert_redirected_to onboarding_path
  end

  test "you're not on it until you're set up" do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
    get leaderboard_path(sort: "today")

    assert_response :success
    assert_select "tr[data-you] td", "—"
    assert_select ".leaderboard__sort[aria-current=page]", "Today"
    assert_select ".leaderboard__you-rank", "—"
  end

  test "an admin isn't on it, not even as you, and their pages still open (D-032)" do
    admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    link_hackatime(users(:orpheus))
    users(:orpheus).project.update!(hackatime_projects: [ "rhythm-game" ])
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!

    get leaderboard_path(sort: "total")
    assert_response :success
    assert_select "tr[data-you]", count: 0
    assert_select ".leaderboard__you-rank", "—"

    get project_path
    assert_response :success
  ensure
    Rails.configuration.x.admin_slack_ids = admins
  end

  test "your account menu shows your public name and your email, never your full name" do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
    get leaderboard_path

    assert_select ".top-bar__account-name", "orph"
    assert_select ".top-bar__account-email", "heidi@hackclub.com"
    assert_select ".top-bar__avatar[aria-label=?]", "Account: orph"
    assert_select ".top-bar__account", text: /Orpheus the Dino/, count: 0
    assert_select ".top-bar__avatar .avatar__initial[data-initial=O]"
  end

  test "set up, you're ranked" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ])
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
    get leaderboard_path

    assert_select "tr[data-you] .leaderboard__rank", "1"
    assert_select "tr[data-you]", /0 hrs/
    assert_select ".leaderboard__eyebrow", false
    assert_select ".leaderboard__note", false
    assert_select "th[data-sorted]", "Hours today"
    assert_select ".leaderboard__streak", false, "no streak mark at zero"
    assert_select ".leaderboard__change", false, "no arrows without a snapshot"
    assert_select ".leaderboard__sort[aria-current=page]", "Today"
    assert_select ".leaderboard__podium .leaderboard__step", 3
    assert_select ".leaderboard__step--empty", 2, "empty steps keep their space"
    assert_select ".leaderboard__you-rank", "#1"

    projects(:orpheus).update!(week_rank: 3, week_rank_on: Date.current)
    get leaderboard_path(sort: "total")
    assert_select "tr[data-you] .leaderboard__change[data-direction=up]", "▲2"
    get leaderboard_path(sort: "today")
    assert_select "th[data-sorted]", "Hours today"
    assert_select ".leaderboard__change", false, "arrows are for the total board"
  end

  test "with no sort the board opens on Today, and Total stays reachable" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ])
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
    get leaderboard_path
    assert_select ".leaderboard__sort[aria-current=page]", "Today"
    assert_select "th[data-sorted]", "Hours today"
    get leaderboard_path(sort: "total")
    assert_select "th[data-sorted]", "Total hours"
  end

  test "today is the viewer's own calendar date, and UTC when signed out" do
    travel_to Time.utc(2026, 11, 1, 20, 0) do # 09:00 on Nov 2 in Auckland, 12:00 on Nov 1 in Los Angeles
      auckland = users(:orpheus).tap { |user| user.update!(timezone: "Pacific/Auckland") }
      la = users(:ana).tap { |user| user.update!(timezone: "America/Los_Angeles") }
      assert_equal Date.new(2026, 11, 2), Leaderboard.date_for(auckland)
      assert_equal Date.new(2026, 11, 1), Leaderboard.date_for(la)
      assert_equal Date.new(2026, 11, 1), Leaderboard.date_for(nil)
    end
  end

  test "the board counts each person's hours on the viewer's today" do
    travel_to Time.utc(2026, 11, 1, 20, 0) do
      users(:orpheus).update!(timezone: "Pacific/Auckland", hackatime_uid: "1001", hackatime_access_token: "token-orpheus")
      users(:ana).update!(hackatime_uid: "9999", hackatime_access_token: "token-ana")
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ])
      users(:ana).streak_activities.create!(activity_date: Date.new(2026, 11, 1), coded_seconds: 3600)
      users(:ana).streak_activities.create!(activity_date: Date.new(2026, 11, 2), coded_seconds: 7200)
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
      get leaderboard_path
      assert_select "tr:not([data-you])", /2\.0 hrs/, "an Auckland viewer's today is Nov 2"
    end
  end

  test "another builder's name links to their Slack profile, and yours is plain" do
    link_hackatime(users(:orpheus))
    users(:ana).update!(hackatime_uid: "9999", hackatime_access_token: "token-ana")
    users(:ana).update!(slack_id: "U0ANA")
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
    get leaderboard_path

    assert_select "tr:not([data-you]) a.slack-name[href='https://hackclub.slack.com/team/U0ANA'][target=_blank][rel~=noopener]", text: /pixelana/
    assert_select "tr[data-you] a.slack-name", false
    users(:ana).update!(slack_id: nil)
    get leaderboard_path
    assert_select "a.slack-name", false
  end

  test "old week and streak links land on the default, and a streak shows beside the name" do
    travel_to Program::ENDS_AT + 1.day # the board defaults to Today, even once Save Point is over
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ])
    now = Time.current.utc.change(hour: 12)
    Hackatime.stubbed_spans = { "1001" => [ 0, 1, 2 ].map { |ago| hackatime_span(now - ago.days, 40) } }
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!

    %w[week streak nonsense].each do |sort|
      get leaderboard_path(sort:)
      assert_response :success
      assert_select ".leaderboard__sort[aria-current=page]", "Today"
    end
    get leaderboard_path(sort: "total")
    assert_select ".leaderboard__sort[aria-current=page]", "Total"
    assert_select "tr[data-you] .leaderboard__streak", "3"
    assert_select "th", text: "Streak", count: 0
  ensure
    Hackatime.stubbed_spans = {}
  end
end
