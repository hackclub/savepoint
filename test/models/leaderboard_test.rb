require "test_helper"

class LeaderboardTest < ActiveSupport::TestCase
  setup do
    @orpheus, @ana = users(:orpheus), users(:ana)
    link_hackatime(@orpheus)
    @ana.update!(hackatime_uid: "1002", hackatime_access_token: "token-heidi")
    @orpheus.project.update!(hackatime_projects: [ "rhythm-game" ])
    @ana.project.update!(hackatime_projects: [ "heidis-game" ])
    # Day one: Orpheus built 1.5 hours, Ana 2.
    at = Time.utc(2026, 10, 24, 15)
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(at, 90) ], "1002" => [ hackatime_span(at, 120) ] }
    travel_to(Time.utc(2026, 10, 25, 12))
    [ @orpheus, @ana ].each { |user| StreakActivity.sync_for_user!(user) }
  end

  teardown do
    travel_back
    Hackatime.stubbed_spans = {}
  end

  test "everyone set up, by total hours, with who's just above and how far" do
    first, second = Leaderboard.places

    assert_equal [ @ana.project, 1, nil ], [ first.project, first.rank, first.above ]
    assert_equal [ @orpheus.project, 2, @ana.project ], [ second.project, second.rank, second.above ]
    assert_nil first.gap_minutes
    assert_equal 30, second.gap_minutes
    assert_equal second, Leaderboard.place_of(@orpheus.project)
  end

  test "admins aren't on the board (D-032)" do
    admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ @ana.slack_id ]

    assert_equal [ @orpheus.project ], Leaderboard.places.map(&:project)
    assert_equal 1, Leaderboard.place_of(@orpheus.project).rank
  ensure
    Rails.configuration.x.admin_slack_ids = admins
  end

  test "someone not set up isn't on it" do
    @ana.project.update!(hackatime_projects: [])
    @ana.update!(hackatime_uid: nil, hackatime_access_token: nil)
    assert_equal [ @orpheus.project ], Leaderboard.places.map(&:project)
  end

  test "a snapshot notes where everyone was, and the board shows how far they've moved since" do
    Leaderboard.snapshot!(Date.new(2026, 10, 24))
    assert_equal [ 1, Date.new(2026, 10, 24) ], [ @ana.project.reload.week_rank, @ana.project.week_rank_on ]
    assert_equal 2, @orpheus.project.reload.week_rank

    # Orpheus builds another hour and passes Ana.
    Hackatime.stubbed_spans["1001"] << hackatime_span(Time.utc(2026, 10, 25, 9), 60)
    StreakActivity.sync_for_user!(@orpheus.reload)

    orpheus, ana = Leaderboard.places
    assert_equal [ @orpheus.project, 1 ], [ orpheus.project, orpheus.change ]
    assert_equal [ @ana.project, -1 ], [ ana.project, ana.change ]
  end

  test "today ranks by the hours in this Save Point day, with total hours breaking ties" do
    # Oct 25, the Save Point day, has no hours yet, so total order stands.
    assert_equal [ @ana.project, @orpheus.project ], Leaderboard.places(sort: "today").map(&:project)

    Hackatime.stubbed_spans["1001"] << hackatime_span(Time.utc(2026, 10, 25, 9), 60)
    StreakActivity.sync_for_user!(@orpheus.reload)
    assert_equal [ @orpheus.project, @ana.project ], Leaderboard.places(sort: "today").map(&:project)
    assert_equal 1.0, @orpheus.project.reload.hours_today
  end

  test "Program.today is the UTC date before the start, then the date at the middle of each 24-hour day" do
    assert_equal Date.new(2026, 10, 23), Program.today(Time.utc(2026, 10, 23, 20, 59))
    assert_equal Date.new(2026, 10, 24), Program.today(Time.utc(2026, 10, 23, 21))
    assert_equal Date.new(2026, 10, 25), Program.today(Time.utc(2026, 10, 24, 21))
    assert_equal Date.new(2026, 10, 25), Program.today(Time.utc(2026, 10, 25, 20, 59))
    assert_equal Date.new(2026, 10, 26), Program.today(Time.utc(2026, 10, 25, 21))
    assert_equal Date.new(2026, 11, 2), Program.today(Time.utc(2026, 11, 2, 20, 59)), "day 10"
  end
end
