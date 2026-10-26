require "test_helper"

class MetricTest < ActiveSupport::TestCase
  setup do
    @orpheus = users(:orpheus)
    @orpheus.streak_activities.create!(activity_date: Date.new(2026, 10, 23), coded_seconds: 3 * 3600)
    @orpheus.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 25 * 60)
    @orpheus.update!(current_streak: 2)
    User.update_all(created_at: Time.utc(2026, 10, 23, 9)) # fixtures are made now, which is after the days here
  end

  test "a day's numbers are as of the end of it, and the undated ones are only taken for today" do
    travel_to Time.utc(2026, 10, 24, 20)

    day6 = Metric.values(Date.new(2026, 10, 23))
    assert_equal [ 1, 3.0, 3.0, 1, 0, 1 ], day6.values_at("builders", "hours_day", "hours", "first_20", "past_5h", "completed")
    assert_not day6.key?("on_streak"), "undated numbers aren't guessed for past days"

    today = Metric.values
    assert_equal [ 1, 0.4, 3.4, 1, 1 ], today.values_at("builders", "hours_day", "hours", "completed", "on_streak")
    assert_equal User.count, today["signed_in"]
  end

  test "a day's builders are the people with 60 seconds or more, not 59" do
    travel_to Time.utc(2026, 10, 24, 20)
    users(:ana).streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 60)
    users(:orpheus).streak_activities.find_by(activity_date: Date.new(2026, 10, 24)).update!(coded_seconds: 59)

    assert_equal 1, Metric.values["builders"]
  end

  test "hours shipped are each project's newest ship as of that day" do
    ship = ->(at, hours) do
      projects(:orpheus).ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                       repo_url: "https://example.com/repo", demo_url: "https://example.com/demo", hours:, created_at: at,
                                       screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
    ship.(Time.utc(2026, 10, 23, 18), 2.5)
    ship.(Time.utc(2026, 10, 24, 18), 3.25)
    travel_to Time.utc(2026, 10, 24, 20)

    assert_equal [ 1, 2.5 ], Metric.values(Date.new(2026, 10, 23)).values_at("shipped", "shipped_hours")
    assert_equal [ 1, 3.25 ], Metric.values.values_at("shipped", "shipped_hours")
    assert_equal [ 0, 0.0 ], Metric.values(Date.new(2026, 10, 22)).values_at("shipped", "shipped_hours")
  end

  test "snapshots are written once per day and metric, and today's is rewritten" do
    travel_to Time.utc(2026, 10, 24, 20)
    Metric.snapshot!
    @orpheus.streak_activities.find_by(activity_date: Date.new(2026, 10, 24)).update!(coded_seconds: 3600)
    Metric.snapshot!

    assert_equal 1, MetricSnapshot.where(day: Date.new(2026, 10, 24), key: "hours_day").count
    assert_equal 1.0, MetricSnapshot.find_by(day: Date.new(2026, 10, 24), key: "hours_day").value
  end

  test "the backfill writes every day of Save Point so far, and history reads them back" do
    travel_to Time.utc(2026, 10, 25, 12)
    Metric.backfill!

    days, values = Metric.history
    assert_equal [ Date.new(2026, 10, 23), Date.new(2026, 10, 24), Date.new(2026, 10, 25) ], days
    assert_equal [ 3.0, 3.4, 3.4 ], days.map { |day| values["hours"][day] }
    assert_equal [ nil, nil, 1 ], days.map { |day| values["on_streak"][day] }
  end

  test "admins on the list add to no number, whatever they do" do
    travel_to Time.utc(2026, 10, 24, 20)
    Project.update_all(created_at: Time.utc(2026, 10, 24, 9)) # fixtures are made now, which is after this day
    ana = users(:ana)
    ana.update!(current_streak: 1)
    ana.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 3600)
    [ @orpheus, ana ].each do |user|
      user.update!(hackatime_uid: "h#{user.id}", hackatime_access_token: "token", slack_muted_at: Time.utc(2026, 10, 24, 9))
      user.project.update!(hackatime_projects: [ "game" ])
      user.project.update_columns(hackatime_seen_seconds: 600)
      user.project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                repo_url: "https://example.com/repo", demo_url: "https://example.com/demo", hours: 2, created_at: Time.utc(2026, 10, 24, 10),
                                screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
      user.nudges.create!(kind: "cheer", arm: "cheer", delivered: true, sent_at: Time.utc(2026, 10, 24, 12))
    end

    assert_equal 2, Metric.values["signed_in"], "with no admins, both count"

    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    values = Metric.values
    assert_equal 1, values["signed_in"], "Orpheus's sign-in isn't counted"
    assert_equal 1, values["pledged"]
    assert_equal [ 1, 1, 1, 1 ], values.values_at("linked", "editor_sent", "set_up", "muted")
    assert_equal 1.0, values["hours_day"], "Orpheus's 25 minutes aren't counted, Ana's hour is"
    assert_equal 1.0, values["hours"]
    assert_equal [ 1, 1 ], values.values_at("builders", "completed")
    assert_equal 1, values["on_streak"], "Orpheus's streak isn't counted"
    assert_equal [ 1, 2.0 ], values.values_at("shipped", "shipped_hours")
    assert_equal 1, values["cheers"], "Orpheus's cheer isn't counted"
  ensure
    Rails.configuration.x.admin_slack_ids = []
  end

  test "pairs and what comes of them leave out any with an admin in them" do
    travel_to Time.utc(2026, 10, 24, 20)
    ana = users(:ana)
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    pair = Pair.create!(first_project: projects(:orpheus), second_project: projects(:ana), started_on: Date.new(2026, 10, 24), created_at: Time.utc(2026, 10, 24, 8))
    pair.pomodoros.create!(started_by: projects(:orpheus), minutes: BuddyPomodoro::LENGTHS.first, started_at: Time.utc(2026, 10, 24, 9), joined_at: Time.utc(2026, 10, 24, 9, 1))
    Reward.create!(user: @orpheus, key: "streak_shoutout")
    Reward.create!(user: ana, key: "streak_shoutout")

    assert_equal [ 0, 0, 1 ], Metric.values.values_at("pairs", "pomodoros", "shoutouts")
    Rails.configuration.x.admin_slack_ids = []
    assert_equal [ 1, 1, 2 ], Metric.values.values_at("pairs", "pomodoros", "shoutouts"), "the same pair counts with no admins"
  ensure
    Rails.configuration.x.admin_slack_ids = []
  end
end
