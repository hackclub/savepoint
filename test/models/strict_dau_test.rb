require "test_helper"

# D-087: the strict DAU. Coding time only. (Its doubtful-link rule was reversed by D-091.)
class StrictDauTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  MARTIAN = "https://github.com/hdhmhf/Minimum-Wage-Martian"

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0NOBODY" ]
    @ana = users(:ana)
    @orpheus = users(:orpheus)
  end

  teardown do
    Rails.configuration.x.admin_slack_ids = @admins
    Hackatime.stubbed_spans = {}
    Hackatime.stubbed_category_seconds = nil
  end

  def span(at, minutes) = { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }

  def bucket(user, minutes_ago, seconds, coding: nil, held: false)
    CodedBucket.create!(user:, bucket_at: CodedBucket.floor(minutes_ago.minutes.ago), seconds: held ? 0 : seconds, unconfirmed_seconds: held ? seconds : 0, coding_seconds: coding)
  end

  def project_for(user, title:, hackatime:, repo: nil, confirmed: false)
    user.project.update_columns(name: title, hackatime_projects: hackatime, repo_url: repo, hackatime_link_confirmed: confirmed, hackatime_auto_linked: false)
    user.project.reload
  end

  # --- Rule 1: coding only ---

  test "a sync asks Hackatime how much of the time was coding and stores it beside the seconds" do
    travel_to Time.utc(2026, 11, 2, 12) do
      link_hackatime(@orpheus)
      project_for(@orpheus, title: "Rhythm", hackatime: [ "rhythm" ])
      coding_from = Time.utc(2026, 11, 2, 9)
      Hackatime.stubbed_spans = { "1001" => [ span(coding_from, 60) ] }
      asked = []
      Hackatime.stubbed_category_seconds = { "1001" => { "coding" => ->(from, to) {
        asked << [ from, to ]
        [ [ to, coding_from + 10.minutes ].min - [ from, coding_from ].max, 0 ].max.to_i
      } } }

      StreakActivity.sync_for_user!(@orpheus)

      day = @orpheus.streak_activities.find_by(activity_date: Date.new(2026, 11, 2))
      assert_equal [ 3600, 600 ], [ day.coded_seconds, day.coding_seconds ], "hours keep all of it; coding is a sixth"
      assert_equal [ 3600, 600 ], @orpheus.coded_buckets.pick(Arel.sql("sum(seconds)"), Arel.sql("sum(coding_seconds)"))
      assert asked.any?
    end
  end

  test "when Hackatime can't say, all of the time counts as coding rather than none" do
    travel_to Time.utc(2026, 11, 2, 12) do
      link_hackatime(@orpheus)
      project_for(@orpheus, title: "Rhythm", hackatime: [ "rhythm" ])
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 2, 9), 30) ] }
      Hackatime.stubbed_category_seconds = { "1001" => { "coding" => :unavailable } }

      StreakActivity.sync_for_user!(@orpheus)

      assert_equal 1800, @orpheus.streak_activities.find_by(activity_date: Date.new(2026, 11, 2)).coding_seconds
    end
  end

  test "the admin DAU counts coding time only" do
    bucket(@ana, 30, 1800, coding: 30)
    bucket(@orpheus, 30, 1800, coding: 90)

    assert_equal 1, AdminSummary.new.dau_today, "ana browsed for half an hour and coded 30 s; orpheus coded a minute and a half"
  end

  test "a piece with no coding figure yet counts in full" do
    bucket(@ana, 30, 600)

    assert_equal 1, AdminSummary.new.dau_today
  end

  test "the day charts and the public count use coding time too" do
    day = Date.new(2026, 10, 25)
    @ana.streak_activities.create!(activity_date: day, coded_seconds: 1800, coding_seconds: 20)
    @orpheus.streak_activities.create!(activity_date: day, coded_seconds: 1800, coding_seconds: 600)

    assert_equal 1, Growth.new(today: day + 1).days.find { |row| row.date == day }.dau
  end

  # --- Rule 2 (reversed by D-090): accounts that share a repo each count ---

  test "D-090: accounts whose projects share a repo each count, and the admin still lists the pair" do
    @ana.project.update_columns(repo_url: MARTIAN)
    @orpheus.project.update_columns(repo_url: "http://www.GitHub.com/hdhmhf/minimum-wage-martian.git")
    bucket(@ana, 30, 600, coding: 600)
    bucket(@orpheus, 30, 600, coding: 600)

    assert_equal 2, AdminSummary.new.dau_today
    pair = AdminSummary.new.shared_games.sole
    assert_equal [ @ana.project.id, @orpheus.project.id ].sort, [ pair[:project_id], pair[:other_project_id] ].sort
    assert_equal [ @ana.public_name, @orpheus.public_name ].sort, [ pair[:name], pair[:other_name] ].sort
  end

  test "different repos, or no repo, are different games" do
    @ana.project.update_columns(repo_url: "https://github.com/a/one")
    @orpheus.project.update_columns(repo_url: "https://github.com/a/two")
    bucket(@ana, 30, 600, coding: 600)
    bucket(@orpheus, 30, 600, coding: 600)

    assert_equal 2, AdminSummary.new.dau_today
    assert_empty AdminSummary.new.shared_games
    @ana.project.update_columns(repo_url: nil)
    @orpheus.project.update_columns(repo_url: nil)
    assert_empty SharedGames.pairs
  end

  test "D-090: accounts that share a game each count in the day charts" do
    day = Date.new(2026, 10, 25)
    @ana.project.update_columns(repo_url: MARTIAN)
    @orpheus.project.update_columns(repo_url: MARTIAN)
    [ @ana, @orpheus ].each { |user| user.streak_activities.create!(activity_date: day, coded_seconds: 1800, coding_seconds: 1800) }

    assert_equal 2, Growth.new(today: day + 1).days.find { |row| row.date == day }.dau
  end

  # --- D-091: a hand-picked link needs no confirmation ---

  test "D-091: a hand-picked link counts however it is named" do
    project = project_for(@ana, title: "Space", hackatime: [ "life-2" ])
    assert project.hackatime_confirmed?

    project.update_columns(hackatime_projects: [ "Other" ])
    assert project.reload.hackatime_confirmed?
  end

  test "D-091: an auto-link still asks, and time on a hand-picked link is not held" do
    travel_to Time.utc(2026, 11, 2, 12) do
      link_hackatime(@orpheus)
      project = project_for(@orpheus, title: "Space", hackatime: [ "life-2" ])
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 1, 15), 30) ] }
      StreakActivity.sync_for_user!(@orpheus)

      day = @orpheus.streak_activities.find_by(activity_date: Date.new(2026, 11, 1))
      assert_equal [ 1800, 0 ], [ day.coded_seconds, day.unconfirmed_seconds ]

      project.update_columns(hackatime_auto_linked: true)
      assert_not project.reload.hackatime_confirmed?
    end
  end

  test "D-091: the migration step releases held time on hand-picked links only, and is safe to run again" do
    project_for(@ana, title: "Space", hackatime: [ "life-2" ])
    project_for(@orpheus, title: "Rhythm", hackatime: [ "rhythm" ])
    @orpheus.project.update_columns(hackatime_auto_linked: true)
    [ @ana, @orpheus ].each do |user|
      user.streak_activities.create!(activity_date: Date.new(2026, 10, 25), coded_seconds: 0, unconfirmed_seconds: 600)
      bucket(user, 30, 300, held: true)
    end

    assert_equal [ @ana.id ], StreakActivity.release_held_on_hand_picked_links!
    assert_equal [ 600, 0 ], @ana.streak_activities.pick(:coded_seconds, :unconfirmed_seconds)
    assert_equal [ 300, 0 ], @ana.coded_buckets.pick(:seconds, :unconfirmed_seconds)
    assert_equal [ 0, 600 ], @orpheus.streak_activities.pick(:coded_seconds, :unconfirmed_seconds), "an unconfirmed auto-link stays held"
    assert_equal [ 0, 300 ], @orpheus.coded_buckets.pick(:seconds, :unconfirmed_seconds)

    assert_empty StreakActivity.release_held_on_hand_picked_links!
    assert_equal [ 600, 0 ], @ana.streak_activities.pick(:coded_seconds, :unconfirmed_seconds)
  end
end
