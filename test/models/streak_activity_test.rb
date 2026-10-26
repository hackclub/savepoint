require "test_helper"

class StreakActivityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ])
  end

  teardown { Hackatime.stubbed_spans = {} }

  # A span of `minutes` starting at `at`, as Hackatime sends it.
  def span(at, minutes)
    { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }
  end

  # Makes the lookup for the stale record's day return it once, as if a competing sync saved the row just after.
  def with_stale_first_lookup(stale)
    original = StreakActivity.method(:find_or_initialize_by)
    served = false
    StreakActivity.singleton_class.define_method(:find_or_initialize_by) do |attrs|
      if !served && attrs[:activity_date] == stale.activity_date
        served = true
        stale
      else
        original.call(attrs)
      end
    end
    yield
  ensure
    StreakActivity.singleton_class.remove_method(:find_or_initialize_by)
  end

  test "days in a row with 20 minutes make the streak, and today doesn't break it until it's over" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [
        span(Time.utc(2026, 10, 30, 15), 25), # Fri
        span(Time.utc(2026, 10, 31, 15), 20), # Sat
        span(Time.utc(2026, 11, 1, 15), 30)  # Sun; nothing yet today
      ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal 3, @user.reload.current_streak
      assert_equal 3, @user.project.streak
    end
  end

  test "a day under 20 minutes breaks it" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [
        span(Time.utc(2026, 10, 30, 15), 25),
        span(Time.utc(2026, 10, 31, 15), 10),
        span(Time.utc(2026, 11, 1, 15), 30),
        span(Time.utc(2026, 11, 2, 9), 20)
      ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal 2, @user.reload.current_streak
    end
  end

  test "building past midnight counts for the night before" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 2, 1), 30) ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal 30 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 1)).coded_seconds
      assert_equal 1, @user.reload.current_streak
    end
  end

  test "a span across 2am is split between the two days" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 2, 1, 50), 30) ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal 10 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 1)).coded_seconds
      assert_equal 20 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 2)).coded_seconds
    end
  end

  test "days follow your timezone" do
    @user.update!(timezone: "America/New_York")
    travel_to Time.utc(2026, 11, 2, 12) do
      # 9pm on the 11th in New York, 1am on the 12th in UTC.
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 2, 1), 30) ] }
      StreakActivity.sync_for_user!(@user)

      assert @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 1)).completed?
    end
  end

  test "tonight's building counts today, even where Hackatime's day has already ended" do
    @user.update!(timezone: "America/Los_Angeles")
    asked = nil
    spans = Hackatime.method(:heartbeat_spans)
    Hackatime.define_singleton_method(:heartbeat_spans) { |user, names, start_date:, end_date:| asked = [ start_date, end_date ]; spans.call(user, names, start_date:, end_date:) }

    # 8pm on the 11th in Los Angeles: already the 12th by Hackatime's clock.
    travel_to Time.utc(2026, 11, 2, 3, 30) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 2, 3), 30) ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal [ Date.new(2026, 10, 22), Date.new(2026, 11, 3) ], asked, "a day either side of the streak days"
      assert_equal 30 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 1)).coded_seconds
      assert_equal 0.5, @user.project.hours_logged
    end
  ensure
    Hackatime.define_singleton_method(:heartbeat_spans, spans)
  end

  test "the next sync goes over the day before too, in case Hackatime's spans moved" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 1, 15), 30) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal 30 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 1)).coded_seconds
    end

    travel_to Time.utc(2026, 11, 2, 18) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 1, 15), 45) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal 45 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 1)).coded_seconds
    end
  end

  test "a sync that loses a race for a new day writes onto the winner's row" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 2, 9), 30) ] }
      today = Date.new(2026, 11, 2)
      winner_seconds = 10 * 60

      # The first lookup returns a stale new record, as if the competing sync saved just after it.
      stale = StreakActivity.new(user_id: @user.id, activity_date: today)
      StreakActivity.create!(user: @user, activity_date: today, coded_seconds: winner_seconds)
      with_stale_first_lookup(stale) { assert_nothing_raised { StreakActivity.sync_for_user!(@user) } }

      assert_equal 1, @user.streak_activities.where(activity_date: today).count
      assert_equal 30 * 60, @user.streak_activities.find_by(activity_date: today).coded_seconds
    end
  end

  test "a day the competing sync completed gets no second cheer" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 2, 9), 30) ] }
      today = Date.new(2026, 11, 2)
      stale = StreakActivity.new(user_id: @user.id, activity_date: today)
      StreakActivity.create!(user: @user, activity_date: today, coded_seconds: 25 * 60)

      assert_no_enqueued_jobs { with_stale_first_lookup(stale) { StreakActivity.sync_for_user!(@user) } }
    end
  end

  test "the first counted span's start is kept as the first coded moment" do
    project = @user.project
    project.update_columns(first_coded_at: nil)
    travel_to Time.utc(2026, 10, 28, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 27, 16, 7), 3), span(Time.utc(2026, 10, 26, 22, 31), 10) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal Time.utc(2026, 10, 26, 22, 31), project.reload.first_coded_at

      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 25, 9), 10), span(Time.utc(2026, 10, 28, 9), 10) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal Time.utc(2026, 10, 26, 22, 31), project.reload.first_coded_at, "it's set once"
    end
  end

  test "time before the hours start isn't the first coded moment" do
    project = @user.project
    project.update_columns(first_coded_at: nil, hours_start_override: Time.utc(2026, 10, 26, 12))
    travel_to Time.utc(2026, 10, 28, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 26, 8), 10), span(Time.utc(2026, 10, 27, 8), 10) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal Time.utc(2026, 10, 27, 8), project.reload.first_coded_at
    end
  end

  test "no time yet leaves the first coded moment empty" do
    @user.project.update_columns(first_coded_at: nil)
    Hackatime.stubbed_spans = { "1001" => [] }
    StreakActivity.sync_for_user!(@user)

    assert_nil @user.project.reload.first_coded_at
  end

  test "someone with days from before first_coded_at existed is read from the first day once" do
    project = @user.project
    travel_to Time.utc(2026, 10, 28, 12) do
      @user.update_columns(streak_synced_at: Time.current)
      @user.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 600)
      project.update_columns(first_coded_at: nil)
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 24, 15, 2), 10) ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal Time.utc(2026, 10, 24, 15, 2), project.reload.first_coded_at
    end
  end

  test "nothing syncs until you've picked Hackatime projects to track" do
    @user.project.update!(hackatime_projects: [])
    Hackatime.stubbed_spans = { "1001" => [ span(Time.current - 1.hour, 30) ] }

    assert_nil StreakActivity.sync_for_user!(@user)
    assert_empty @user.streak_activities
  end

  test "the week shows which days you hit 20 minutes" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 1, 15), 30) ] }
      StreakActivity.sync_for_user!(@user)

      week = @user.streak_week
      assert_equal %w[S M T W T F S], week.map { |day| day[:letter] }
      assert_equal [ true, false ], week.first(2).map { |day| day[:completed] }
      assert week[1][:today]
    end
  end

  test "changing your Hackatime projects rebuilds the streak from the start" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 1, 15), 30) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal 1, @user.reload.current_streak

      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 31, 15), 30), span(Time.utc(2026, 11, 1, 15), 30) ] }
      perform_enqueued_jobs { @user.project.update!(hackatime_projects: [ "rhythm-game", "beat-sheet-art" ]) }

      assert_equal 2, @user.reload.current_streak
    end
  end

  test "with no Hackatime projects left, there's no streak" do
    @user.streak_activities.create!(activity_date: Date.current, coded_seconds: 30 * 60)
    @user.update_column(:current_streak, 1)

    @user.project.update_column(:hackatime_projects, [])
    @user.refresh_streak!

    assert_equal 0, @user.reload.current_streak
    assert_empty @user.streak_activities
  end

  # D-055: time counts from the launch moment. A launch at 01:14:39 UTC is local Oct 22 west of UTC and Oct 23 east of it.
  LAUNCH = Time.utc(2026, 10, 23, 1, 14, 39)

  def with_launch(time = LAUNCH)
    old = [ Program::STARTS_AT, Program::FIRST_STREAK_DATE ]
    Program.send(:remove_const, :STARTS_AT)
    Program.send(:remove_const, :FIRST_STREAK_DATE)
    Program.const_set(:STARTS_AT, time)
    Program.const_set(:FIRST_STREAK_DATE, (time - 14.hours).utc.to_date)
    yield
  ensure
    Program.send(:remove_const, :STARTS_AT)
    Program.send(:remove_const, :FIRST_STREAK_DATE)
    Program.const_set(:STARTS_AT, old[0])
    Program.const_set(:FIRST_STREAK_DATE, old[1])
  end

  def seconds_on(date) = @user.streak_activities.find_by(activity_date: date)&.coded_seconds.to_i

  test "the first streak day is the one holding the launch for someone at UTC-12" do
    with_launch { assert_equal Date.new(2026, 10, 22), Program::FIRST_STREAK_DATE }
    with_launch(Time.utc(2026, 10, 23, 21)) { assert_equal Date.new(2026, 10, 23), Program::FIRST_STREAK_DATE }
  end

  test "a span across the launch keeps only the time after it" do
    with_launch do
      travel_to LAUNCH + 1.day do
        Hackatime.stubbed_spans = { "1001" => [ span(LAUNCH - 10.minutes, 30) ] }
        StreakActivity.sync_for_user!(@user)

        assert_equal 20 * 60, seconds_on(Date.new(2026, 10, 22)), "01:04 to 01:34 UTC is still the night of the 22nd"
        assert_equal 20 * 60, @user.streak_activities.sum(:coded_seconds)
      end
    end
  end

  test "time before the launch counts nothing" do
    with_launch do
      travel_to LAUNCH + 1.day do
        Hackatime.stubbed_spans = { "1001" => [ span(LAUNCH - 3.hours, 60), span(LAUNCH - 1.day, 90) ] }
        StreakActivity.sync_for_user!(@user)

        assert_equal 0, @user.streak_activities.sum(:coded_seconds)
        assert_equal 0, @user.reload.current_streak
      end
    end
  end

  test "after the launch, a UTC-5 builder's time on their local Oct 22 is kept and counted everywhere" do
    @user.update!(timezone: "Etc/GMT+5")
    with_launch do
      travel_to LAUNCH + 2.days do
        # 20:24 to 23:24 on Oct 22 local, after the launch; and an hour before it, which is dropped.
        Hackatime.stubbed_spans = { "1001" => [ span(LAUNCH + 10.minutes, 180), span(LAUNCH - 2.hours, 60) ] }
        StreakActivity.sync_for_user!(@user)

        assert_equal 180 * 60, seconds_on(Date.new(2026, 10, 22))
        assert_equal 3.0, @user.hours_in(Program::FIRST_STREAK_DATE..)
        assert_equal 3.0, Metric.values(Date.new(2026, 10, 25))["hours"]
        assert_equal 3.0, PublicStats.new.to_h[:totals][:hours]
        assert_equal 3.0, Ship.new(project: @user.project, hours: 10, created_at: Time.current).counted_hours
        assert_equal 3.0, @user.project.hours_logged
      end
    end
  end

  test "a UTC+8 builder's local Oct 23 before the launch is left out" do
    @user.update!(timezone: "Asia/Singapore")
    with_launch do
      travel_to LAUNCH + 2.days do
        # 03:00 to 08:00 on Oct 23 local is 19:00 to 00:00 UTC on the 22nd, before the launch. 10:14 local is after it.
        Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 22, 19), 300), span(LAUNCH + 1.hour, 45) ] }
        StreakActivity.sync_for_user!(@user)

        assert_equal 45 * 60, seconds_on(Date.new(2026, 10, 23))
        assert_equal 0.8, @user.hours_in(Program::FIRST_STREAK_DATE..)
      end
    end
  end

  test "a rebuild from the start fixes old rows and cheers nobody twice" do
    with_launch do
      travel_to LAUNCH + 1.day do
        Hackatime.stubbed_spans = { "1001" => [ span(LAUNCH - 3.hours, 60), span(LAUNCH + 1.hour, 30) ] }
        # What the old sync left: the pre-launch hour counted as well.
        @user.streak_activities.create!(activity_date: Date.new(2026, 10, 22), coded_seconds: 90 * 60)
        @user.update_column(:streak_synced_at, Time.current)

        assert_enqueued_with(job: NudgeCheerJob) { StreakActivity.sync_for_user!(@user, from_start: true) }
        assert_equal [ 0, 30 * 60 ], [ seconds_on(Date.new(2026, 10, 22)), seconds_on(Date.new(2026, 10, 23)) ]

        assert_no_enqueued_jobs(only: NudgeCheerJob) { StreakSyncJob.perform_now(@user.id, from_start: true) }
        assert_no_difference -> { Reward.count } do
          StreakActivity.sync_for_user!(@user, from_start: true)
        end
      end
    end
  end

  test "a rebuild that finds yesterday already complete sends no cheer" do
    with_launch do
      travel_to LAUNCH + 1.day do
        Hackatime.stubbed_spans = { "1001" => [ span(LAUNCH + 1.hour, 30) ] }
        StreakActivity.sync_for_user!(@user)
        clear_enqueued_jobs

        assert_no_enqueued_jobs(only: NudgeCheerJob) { StreakActivity.sync_for_user!(@user, from_start: true) }
      end
    end
  end

  test "D-084: time on an unconfirmed auto-link is synced but held, and confirming counts it at once" do
    @user.project.update_columns(hackatime_auto_linked: true)
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 1, 15), 30) ] }
      StreakActivity.sync_for_user!(@user)

      day = @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 1))
      assert_equal 0, day.coded_seconds
      assert_equal 30 * 60, day.unconfirmed_seconds
      assert_equal 0.0, @user.hours_in(Date.new(2026, 11, 1)..Date.new(2026, 11, 1))
      assert_equal 0, @user.reload.current_streak

      @user.project.update!(hackatime_auto_linked: false)

      day.reload
      assert_equal 30 * 60, day.coded_seconds
      assert_equal 0, day.unconfirmed_seconds
      assert_equal 0.5, @user.hours_in(Date.new(2026, 11, 1)..Date.new(2026, 11, 1))
      assert_equal 1, @user.reload.current_streak
    end
  end

  test "D-084: a link picked by hand counts straight away" do
    travel_to Time.utc(2026, 11, 2, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 11, 1, 15), 30) ] }
      StreakActivity.sync_for_user!(@user)

      day = @user.streak_activities.find_by(activity_date: Date.new(2026, 11, 1))
      assert_equal [ 30 * 60, 0 ], [ day.coded_seconds, day.unconfirmed_seconds ]
    end
  end
end
