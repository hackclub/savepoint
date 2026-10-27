require "test_helper"

# D-087: the strict DAU. Coding time only, a doubtful hand-picked link held until a Yes.
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

    assert_equal 1, AdminSummary.new.dau_24h, "ana browsed for half an hour and coded 30 s; orpheus coded a minute and a half"
  end

  test "a piece with no coding figure yet counts in full" do
    bucket(@ana, 30, 600)

    assert_equal 1, AdminSummary.new.dau_24h
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

    assert_equal 2, AdminSummary.new.dau_24h
    pair = AdminSummary.new.shared_games.sole
    assert_equal [ @ana.project.id, @orpheus.project.id ].sort, [ pair[:project_id], pair[:other_project_id] ].sort
    assert_equal [ @ana.public_name, @orpheus.public_name ].sort, [ pair[:name], pair[:other_name] ].sort
  end

  test "different repos, or no repo, are different games" do
    @ana.project.update_columns(repo_url: "https://github.com/a/one")
    @orpheus.project.update_columns(repo_url: "https://github.com/a/two")
    bucket(@ana, 30, 600, coding: 600)
    bucket(@orpheus, 30, 600, coding: 600)

    assert_equal 2, AdminSummary.new.dau_24h
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

  # --- Rule 3: doubtful hand-picked links ---

  test "a Hackatime name that shares nothing with the title or repo is doubtful" do
    project = project_for(@ana, title: "Space", hackatime: [ "Chill cafe" ])
    assert project.hackatime_link_doubtful?, "Chill cafe on a game called Space"
    project.update_columns(repo_url: "https://github.com/ana/chill-cafe")
    assert_not project.reload.hackatime_link_doubtful?, "the repo says chill-cafe"
  end

  test "one matching name among several is enough" do
    project = project_for(@ana, title: "Dust Bunny, Dusty Beetle", hackatime: [ "Dusty Beetle" ])
    assert_not project.hackatime_link_doubtful?
    project.update_columns(hackatime_projects: [ "Dusty Beetle", "Other" ])
    assert_not project.hackatime_link_doubtful?
  end

  test "Other is always doubtful, even for a game with other in its title" do
    assert project_for(@ana, title: "Other Side", hackatime: [ "Other" ]).hackatime_link_doubtful?
  end

  test "case, hyphens and generic words are ignored" do
    assert_not project_for(@ana, title: "Minimum Wage Martian", hackatime: [ "minimum-wage-martian" ]).hackatime_link_doubtful?
    assert_not project_for(@ana, title: "Space Pirates", hackatime: [ "SpacePirates" ]).hackatime_link_doubtful?
    assert project_for(@ana, title: "Space Pirates", hackatime: [ "jame-gam-game" ]).hackatime_link_doubtful?
    assert project_for(@ana, title: "Pirate Game", hackatime: [ "my-game-project" ]).hackatime_link_doubtful?, "game and project say nothing"
    assert project_for(@ana, title: "3 Apples Tall", hackatime: [ "Jame Gam" ]).hackatime_link_doubtful?
    assert_not project_for(@ana, title: "Hecate", hackatime: [ "Jame-Gam-Game-Jam-Game" ], repo: "https://example.com/x/Jame-Gam-Game-Jam-Game").hackatime_link_doubtful?, "the repo has that very name"
    assert_not project_for(@ana, title: "Minimum Wage Martian", hackatime: [ "Minimum Wage Martians" ]).hackatime_link_doubtful?
    assert project_for(@ana, title: "Minimum Wage Martian", hackatime: [ "Untitled Restuarant Game" ]).hackatime_link_doubtful?
  end

  test "no linked Hackatime project is not doubtful, and a repo name can match" do
    project = project_for(@ana, title: "Zork", hackatime: [], repo: nil)
    assert_not project.hackatime_link_doubtful?
    project.update_columns(hackatime_projects: [ "martian-run" ], repo_url: "https://github.com/x/Martian-Run")
    assert_not project.reload.hackatime_link_doubtful?
  end

  test "a doubtful link is unconfirmed, a Yes confirms it for good, and a new project asks again" do
    project = project_for(@ana, title: "Space", hackatime: [ "Chill cafe" ])
    assert_not project.hackatime_confirmed?

    project.update!(hackatime_link_confirmed: true)
    assert project.hackatime_confirmed?
    project.update!(name: "Something else", repo_url: "https://github.com/a/b")
    assert project.reload.hackatime_confirmed?, "the Yes stays when the title changes"

    project.hackatime_project_names = [ "Chill cafe" ]
    assert project.hackatime_link_confirmed?, "picking the same project again keeps the Yes"
    project.hackatime_project_names = [ "Chill cafe", "Another" ]
    assert_not project.hackatime_link_confirmed?
  end

  test "time on a doubtful link is held, and a Yes counts it at once" do
    travel_to Time.utc(2026, 11, 2, 12) do
      link_hackatime(@orpheus)
      project = project_for(@orpheus, title: "Space", hackatime: [ "Chill cafe" ])
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 1, 15), 30) ] }
      StreakActivity.sync_for_user!(@orpheus)

      day = @orpheus.streak_activities.find_by(activity_date: Date.new(2026, 11, 1))
      assert_equal [ 0, 1800 ], [ day.coded_seconds, day.unconfirmed_seconds ]

      project.update!(hackatime_link_confirmed: true)
      day.reload
      assert_equal [ 1800, 0 ], [ day.coded_seconds, day.unconfirmed_seconds ]
    end
  end

  test "the one-off task holds time already stored for doubtful links" do
    project_for(@ana, title: "Space", hackatime: [ "Chill cafe" ])
    project_for(@orpheus, title: "Rhythm", hackatime: [ "rhythm" ])
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 25), coded_seconds: 600)
    @orpheus.streak_activities.create!(activity_date: Date.new(2026, 10, 25), coded_seconds: 600)
    bucket(@ana, 30, 300)

    Rails.application.load_tasks
    assert_output(/1 doubtful links.*project ids #{@ana.project.id}\n/m) { Rake::Task["hackatime:hold_doubtful_links"].execute }

    assert_equal [ 0, 600 ], @ana.streak_activities.pick(:coded_seconds, :unconfirmed_seconds)
    assert_equal [ 600, 0 ], @orpheus.streak_activities.pick(:coded_seconds, :unconfirmed_seconds)
    assert_equal [ 0, 300 ], @ana.coded_buckets.pick(:seconds, :unconfirmed_seconds)
  end
end
