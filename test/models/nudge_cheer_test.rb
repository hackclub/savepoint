require "test_helper"

class NudgeCheerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
    # Signed up before the stickers (Reward::STICKERS_SINCE), so a day's span never reads as their first hour. The
    # fixture's created_at is the real clock, and on Oct 25 it would.
    @user.update_column(:created_at, Time.utc(2026, 10, 16))
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)

    @sent = []
    sent = @sent
    @dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil| sent << [ slack_id, text, blocks ] && SlackMessage.new("D0ORPHEUS", "1.0") }
  end

  teardown do
    SlackBot.define_singleton_method(:dm, @dm)
    Hackatime.stubbed_spans = {}
  end

  def at(day = 8, hour: 20, min: 0)
    # `day` counts from 1 on Oct 17, so day 8 is Oct 25.
    Time.find_zone("America/New_York").local(2026, 10, 1, hour, min) + (day + 16).days
  end

  def span(at, minutes)
    { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }
  end

  # Hackatime says they built `minutes` on each of these evenings, and we sync.
  def built!(*days, minutes: 25, now: at)
    Hackatime.stubbed_spans = { "1001" => days.map { |day| span(at(day, hour: 17), minutes) } }
    travel_to(now) { StreakActivity.sync_for_user!(@user.reload) }
  end

  def cheer(built_on = Date.new(2026, 10, 25), now = at)
    travel_to(now) { NudgeCheerJob.perform_now(@user.id, built_on) }
    @user.nudges.cheers.last
  end

  test "crossing the day's 20 minutes queues a cheer, and only the once" do
    assert_enqueued_with(job: NudgeCheerJob, args: [ @user.id, Date.new(2026, 10, 25) ]) { built!(8, minutes: 20) }
    assert_no_enqueued_jobs(only: NudgeCheerJob) { built!(8, minutes: 50) }
  end

  test "a first sync that finds yesterday and today both done cheers once, for today" do
    assert_enqueued_with(job: NudgeCheerJob, args: [ @user.id, Date.new(2026, 10, 25) ]) { built!(7, 8) }
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == NudgeCheerJob }
  end

  test "a cheer right after the slot nudge waits the hour" do
    Hackatime.stubbed_spans = {}
    slot = at(8, hour: 19, min: 5)
    assert travel_to(slot) { Nudge.deliver_to(@user.reload, slot) }.delivered

    built!(8, now: at(8, hour: 19, min: 40))
    assert_enqueued_with(job: NudgeCheerJob, args: [ @user.id, Date.new(2026, 10, 25) ], at: slot + 1.hour) do
      cheer(Date.new(2026, 10, 25), at(8, hour: 19, min: 40))
    end
    assert_equal 1, @sent.size

    assert cheer(Date.new(2026, 10, 25), slot + 1.hour).delivered
    assert_equal 2, @sent.size
  end

  test "a reward's DM goes first, and the cheer an hour on" do
    built!(6, 7, 8)
    assert @user.rewards.exists?(key: "gold_star")
    assert_equal at, @user.reload.slack_dmed_at

    assert_enqueued_with(job: NudgeCheerJob, args: [ @user.id, Date.new(2026, 10, 25) ], at: at + 1.hour) { cheer }
    assert_empty @sent
    assert cheer(Date.new(2026, 10, 25), at + 1.hour).delivered
  end

  test "a project linking itself at your slot is the day's message: no nudge, one cheer, an hour on" do
    @user.project.update!(hackatime_projects: [], hackatime_baseline: [ "dotfiles" ], hackatime_baseline_seconds: { "dotfiles" => 11_160 })
    Hackatime.stubbed_spans = { "1001" => [ span(at(7, hour: 17), 51), span(at(8, hour: 17), 56) ] }
    slot = at(8, hour: 19, min: 5)

    nudge = nil
    assert_enqueued_with(job: NudgeCheerJob, args: [ @user.id, Date.new(2026, 10, 25) ]) do
      nudge = travel_to(slot) { Nudge.deliver_to(@user.reload, slot) }
    end
    assert_nil nudge
    assert_empty @sent
    assert_equal [ "rhythm-game" ], @user.project.reload.hackatime_projects
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == NudgeCheerJob }, "one cheer, not one for each day"
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == SlackMessageJob }

    assert_enqueued_with(job: NudgeCheerJob, args: [ @user.id, Date.new(2026, 10, 25) ], at: slot + 1.hour) { cheer(Date.new(2026, 10, 25), slot) }
    assert_empty @sent

    assert cheer(Date.new(2026, 10, 25), slot + 1.hour).delivered
    cheer(Date.new(2026, 10, 24), slot + 2.hours)
    assert_equal 1, @sent.size, "yesterday's cheer never goes after today's"
  end

  test "a cheer that's stopped being owed isn't held around" do
    built!(8)
    cheer
    assert_no_enqueued_jobs(only: NudgeCheerJob) { cheer(Date.new(2026, 10, 25), at(8, hour: 20, min: 30)) }
  end

  test "a day under 20 minutes gets no cheer, and nor does one from before yesterday" do
    assert_no_enqueued_jobs(only: NudgeCheerJob) { built!(8, minutes: 15) }
    assert_no_enqueued_jobs(only: NudgeCheerJob) { built!(6, now: at(8)) }
  end

  test "the bot cheers you on right after, in a way the bandit picks" do
    built!(8)
    nudge = cheer

    assert nudge.delivered
    assert_equal [ "cheer", "cheer", Date.new(2026, 10, 25) ], [ nudge.kind, nudge.bucket, nudge.built_on ]
    assert_includes Nudge::Bandit::ARMS["cheer"], nudge.arm
    assert_equal({ minutes: 25, day: "today", next_day: "tomorrow" }, Nudge::Context.new(@user, at, built_on: nudge.built_on).vars.slice(:minutes, :day, :next_day))
    assert_equal "U0ORPHEUS", @sent.sole.first
  end

  test "one cheer per day, and none once the bot's stopped" do
    built!(8)
    cheer
    cheer(Date.new(2026, 10, 25), at(8, hour: 21))
    assert_equal 1, @user.nudges.cheers.delivered.count
    assert_equal 1, @sent.size

    @user.update!(slack_muted_at: Time.current)
    built!(8, 9, now: at(9))
    cheer(Date.new(2026, 10, 26), at(9))
    assert_equal 1, @sent.size
  end

  test "a late night's cheer waits for the morning, and says yesterday" do
    built!(8, now: at(8, hour: 23))
    assert_enqueued_with(job: NudgeCheerJob, args: [ @user.id, Date.new(2026, 10, 25) ], at: at(9, hour: 8)) do
      cheer(Date.new(2026, 10, 25), at(8, hour: 23))
    end
    assert_empty @sent

    nudge = cheer(Date.new(2026, 10, 25), at(9, hour: 8))
    assert nudge.delivered
    assert_equal({ day: "yesterday", next_day: "today" }, Nudge::Context.new(@user, at(9, hour: 8), built_on: nudge.built_on).vars.slice(:day, :next_day))
    assert_not_includes nudge.text, "tomorrow"
  end

  test "a cheer worked if they built 20 minutes the next day" do
    built!(8)
    worked = cheer
    built!(8, 9, now: at(9, hour: 18))
    other = @user.nudges.create!(kind: "cheer", arm: "cheer_done", bucket: "cheer", built_on: Date.new(2026, 10, 26),
                                 delivered: true, sent_at: at(9, hour: 18))

    travel_to(at(10, hour: 1)) { Nudge.score_due }
    assert_nil worked.reload.reward, "the next day isn't over until 2am"

    travel_to(at(10, hour: 3)) { Nudge.score_due }
    assert_equal 1, worked.reload.reward
    assert_nil other.reload.reward, "its day after is still going"

    travel_to(at(11, hour: 3)) { Nudge.score_due }
    assert_equal 0, other.reload.reward
  end

  test "a slot nudge before building and a cheer after can share a day, and cheers don't use up the weekly cap" do
    Hackatime.stubbed_spans = {}
    slot = travel_to(at(8, hour: 19, min: 5)) { Nudge.deliver_to(@user.reload, at(8, hour: 19, min: 5)) }
    assert slot.delivered

    built!(8, now: at(8, hour: 21))
    assert cheer(Date.new(2026, 10, 25), at(8, hour: 21)).delivered

    5.times { |i| @user.nudges.create!(kind: "cheer", arm: "cheer_done", bucket: "cheer", built_on: at(7).to_date - i, delivered: true, sent_at: at(7) - i.days) }
    Hackatime.stubbed_spans = {}
    @user.streak_activities.delete_all
    assert Nudge::Context.new(@user.reload, at(9, hour: 19, min: 5)).may_nudge?, "six cheers this week don't stop the slot nudge"
  end
end
