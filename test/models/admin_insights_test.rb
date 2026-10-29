require "test_helper"
require_relative "../support/admin_mcp_helpers"

# The sections of the admin home that AdminSummary gathers from AdminInsights: goal pace, prize spend, sign-up day, ships, nudges.
class AdminInsightsTest < ActiveSupport::TestCase
  include AdminMcpHelpers

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    travel_to Time.utc(2026, 10, 28, 12)
    @ana = users(:ana)
    @goal = Prize.find("u2c")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  # Goal pace.

  test "someone who has the hours for their goal has reached it" do
    track(@ana, @goal.hours)

    assert_equal({ reached: 1, on_track: 0, behind: 0, claimed: 0 }, AdminInsights::GoalPace.call.except(:goals))
  end

  test "someone who needs more a day than they pledged is behind" do
    track(@ana, 0)

    assert_equal [ 0, 0, 1 ], AdminInsights::GoalPace.call.values_at(:reached, :on_track, :behind)
  end

  test "someone who needs no more a day than they pledged is on track, up to exactly their pledge" do
    pledged = projects(:ana).pace_minutes
    days = projects(:ana).days_left
    track(@ana, @goal.hours - pledged * days / 60.0)

    assert_equal [ 0, 1, 0 ], AdminInsights::GoalPace.call.values_at(:reached, :on_track, :behind), "needing exactly what they pledged"

    @ana.streak_activities.update_all(coded_seconds: (@goal.hours - pledged * days / 60.0 - 1) * 3600)
    assert_equal [ 0, 0, 1 ], AdminInsights::GoalPace.new.call.values_at(:reached, :on_track, :behind), "an hour more to go than their pledge covers"

    projects(:ana).update_columns(pace_minutes: pledged + 60)
    assert_equal [ 0, 1, 0 ], AdminInsights::GoalPace.new.call.values_at(:reached, :on_track, :behind), "the pledge is the bar, not the goal's own pace"
  end

  test "someone with no pledge is held to their goal's pace from when their hours start, not from the launch (D-065)" do
    started = Time.utc(2026, 10, 27, 12) # a jame gam submission moves their start past the launch
    goal = Prize::ALL.max_by(&:hours) # enough hours that a day's pace isn't more than the whole goal
    projects(:ana).update_columns(jame_gam_submitted_at: started, prize_key: goal.key)
    from_start, from_launch = [ started, Program::STARTS_AT ].map { |from| goal.pace_minutes(from:) }
    assert_operator from_start, :>, from_launch
    days = projects(:ana).days_left
    status = lambda do # the column is NOT NULL, so the fallback is only a guard: call it without a pledge
      project = Project.find(projects(:ana).id)
      project.define_singleton_method(:pace_minutes) { nil }
      AdminInsights::GoalPace.new.send(:status, project, goal)
    end

    track(@ana, goal.hours - (from_start + 5) * days / 60.0) # needs 5 minutes more a day than the pace from their start
    assert_equal :behind, status.call, "behind, though no more than the launch's pace"

    @ana.streak_activities.update_all(coded_seconds: (goal.hours - from_start * days / 60.0) * 3600)
    assert_equal :on_track, status.call, "needing exactly the pace from their start"
  end

  test "claimed goals are counted apart, and admins and people with no goal are left out" do
    track(@ana, 0)
    claim(projects(:ana), "u2c", "waiting")
    track(users(:orpheus), 0)
    projects(:orpheus).update_columns(prize_key: nil)

    pace = AdminInsights::GoalPace.call

    assert_equal [ 1, 0 ], [ pace[:claimed], pace[:goals].size ]
    assert_equal 0, pace[:reached] + pace[:on_track] + pace[:behind]
  end

  # Prize spend.

  test "prize spend adds up the cost of orders by status, and projects the goals of people who have reached it or are on track" do
    track(@ana, @goal.hours)
    claim(projects(:ana), "aseprite", "waiting")
    claim(projects(:ana), "steam25", "ordered")
    claim(projects(:orpheus), "k2", "waiting")

    spend = AdminInsights::PrizeSpend.call(AdminInsights::GoalPace.call)

    assert_equal({ count: 1, dollars: 19.99 }, spend[:waiting], "the admin's order isn't counted")
    assert_equal({ count: 1, dollars: 25.0 }, spend[:ordered])
    assert_equal 44.99, spend[:claimed_dollars]
    assert_equal({ count: 1, dollars: @goal.cost.to_f }, spend[:projected])
  end

  test "prize spend is all zeros with no orders and nobody on pace" do
    spend = AdminInsights::PrizeSpend.call(AdminInsights::GoalPace.call)

    assert_equal [ 0, 0.0, 0.0, 0 ], [ spend[:waiting][:count], spend[:waiting][:dollars], spend[:claimed_dollars], spend[:projected][:count] ]
  end

  # Built on the sign-up day.

  test "the share who built 20 minutes on the day they signed up, a row for each day, nil where nobody did" do
    bea = User.create!(hca_id: "ident!bea", email: "bea@hackclub.com", name: "Bea", first_name: "Bea", slack_id: "U0BEA")
    User.update_all(created_at: Time.utc(2026, 10, 23, 9))
    bea.update_columns(created_at: Time.utc(2026, 10, 24, 9))
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 23), coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    bea.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: StreakActivity::DAILY_GOAL_SECONDS - 1)
    users(:orpheus).streak_activities.create!(activity_date: Date.new(2026, 10, 23), coded_seconds: 3600)

    rows = AdminInsights::SignUpDay.call(dates: (Date.new(2026, 10, 23)..Date.new(2026, 10, 25)).to_a)

    assert_equal({ date: Date.new(2026, 10, 23), signed_up: 1, built: 1, percent: 100 }, rows[0], "Ana, not the admin")
    assert_equal({ date: Date.new(2026, 10, 24), signed_up: 1, built: 0, percent: 0 }, rows[1], "19m59s isn't 20 minutes")
    assert_equal({ date: Date.new(2026, 10, 25), signed_up: 0, built: 0, percent: nil }, rows[2])
    assert_empty AdminInsights::SignUpDay.call(dates: [])
  end

  # Ships and the review wait.

  test "ships a day, and when the oldest one in review was made" do
    old = ship(projects(:ana))
    old.update_columns(created_at: Time.utc(2026, 10, 25, 8))
    ship(projects(:ana), status: "approved").update_columns(created_at: Time.utc(2026, 10, 26, 8))
    ship(projects(:orpheus)).update_columns(created_at: Time.utc(2026, 10, 25, 9))

    flow = AdminInsights::ShipFlow.call(dates: (Date.new(2026, 10, 25)..Date.new(2026, 10, 27)).to_a)

    assert_equal [ 1, 1, 0 ], flow[:days].map { |day| day[:ships] }
    assert_equal [ 1, Time.utc(2026, 10, 25, 8) ], [ flow[:in_review], flow[:oldest_in_review_at] ]
  end

  test "at the last funnel steps, ships in review and unclaimed approvals are waiting, not lost" do
    create_insights_views
    funnel = { participants: 5, steps: [ { key: "shipped", count: 4 }, { key: "approved", count: 1 }, { key: "claimed", count: 0 } ] }
    track(@ana, 11)
    ship(projects(:ana)).update_columns(created_at: Time.utc(2026, 10, 25, 8))

    assert_equal({ approved: 1, claimed: 1 }, ParticipantFunnel.waiting(funnel))

    projects(:ana).ships.update_all(approved_columns(1))
    ship(projects(:ana)).update_columns(created_at: Time.utc(2026, 10, 26, 8))
    assert_equal 0, ParticipantFunnel.waiting(funnel)[:approved], "someone who has an approved ship isn't waiting for their first"
  end

  test "with nothing in review there is no oldest" do
    assert_nil AdminInsights::ShipFlow.call(dates: [])[:oldest_in_review_at]
  end

  # Nudges.

  test "the share of nudges followed by building the day they went or the next, by kind, without cheers, admins or recent ones" do
    5.times { |i| nudge(@ana, "bandit", Time.utc(2026, 10, 24, 15) + i.minutes) }
    nudge(@ana, "setup", Time.utc(2026, 10, 25, 15))
    nudge(@ana, "cheer", Time.utc(2026, 10, 24, 15))
    nudge(@ana, "bandit", Time.utc(2026, 10, 27, 15))
    nudge(users(:orpheus), "bandit", Time.utc(2026, 10, 24, 15))
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 25), coded_seconds: 60)

    results = AdminInsights::NudgeResults.call

    assert_equal({ n: 6, built: 6, percent: 100 }, results[:total])
    assert_equal [ [ "bandit", 5 ], [ "other kinds", 1 ] ], results[:kinds].map { |row| [ row[:kind], row[:n] ] }, "kinds under #{AdminInsights::NudgeResults::ENOUGH} fold together"
  end

  test "a nudge with no time coded the day it went or the next didn't work" do
    nudge(@ana, "bandit", Time.utc(2026, 10, 24, 15))
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 26), coded_seconds: 3600)

    assert_equal({ n: 1, built: 0, percent: 0 }, AdminInsights::NudgeResults.call[:total])
    assert_equal({ n: 0, built: 0, percent: nil }, AdminInsights::NudgeResults.new(Date.new(2026, 10, 20)).call[:total])
  end

  private
    def track(user, hours)
      user.update!(hackatime_uid: "uid-#{user.id}", hackatime_access_token: "token")
      user.project.update_columns(hackatime_projects: [ "pong" ])
      user.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: hours * 3600) if hours.positive?
    end

    def claim(project, prize_key, status)
      project.orders.new(prize_key:, hours: 1, status:).save!(validate: false)
    end

    def ship(project, status: "in_review")
      project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                            repo_url: "https://example.com/repo", demo_url: "https://example.com/demo", hours: 1,
                            **(status == "approved" ? approved_columns(1) : { status: }),
                            screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end

    def nudge(user, kind, sent_at)
      user.nudges.create!(kind:, arm: "test_arm", bucket: "test", delivered: true, sent_at:)
    end
end
