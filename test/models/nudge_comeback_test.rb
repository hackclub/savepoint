require "test_helper"

# The comeback DM after a missed day, and the free sticker pack for coming back (D-078).
class NudgeComebackTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
    # Signed up before the stickers (Reward::STICKERS_SINCE), so no day's span reads as their first hour.
    @user.update_column(:created_at, Time.utc(2026, 10, 16))
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)
    @user.nudges.create!(kind: "milestone", arm: "first_session", delivered: true, sent_at: at_slot(6))
    built_on(7) # they built on day 7 and then missed day 8, so day 9's slot is when the comeback goes

    @sent = []
    sent = @sent
    @dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil| sent << [ slack_id, text, blocks ] && SlackMessage.new("D0ORPHEUS", "1.0") }
  end

  teardown do
    SlackBot.define_singleton_method(:dm, @dm)
    Hackatime.stubbed_spans = {}
  end

  # `day` counts from 1 on Oct 17, so day 6 is Oct 23, Save Point's first date.
  def at_slot(day = 9, hour: 19, min: 5)
    Time.find_zone("America/New_York").local(2026, 10, 1, hour, min) + (day + 16).days
  end

  def span(at, minutes)
    { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }
  end

  def built_on(*days, minutes: 25)
    Hackatime.stubbed_spans = { "1001" => days.map { |day| span(at_slot(day, hour: 17), minutes) } }
  end

  def deliver(at = at_slot)
    travel_to(at) { Nudge.deliver_to(@user.reload, at) }
  end

  def earn_packs(count, keys: Reward::COMEBACK_STICKER_KEYS)
    keys.first(count).each { |key| @user.rewards.create!(key:) }
  end

  test "someone who built before and missed yesterday gets one DM, which promises stickers" do
    nudge = deliver

    assert_equal [ "comeback", "comeback_stickers", true ], [ nudge.kind, nudge.arm, nudge.stickers_promised ]
    assert_equal at_slot.to_date - 1, nudge.built_on, "the day they missed"
    assert nudge.delivered
    assert_match(/sticker/, nudge.text)
    assert_no_match(/%\{/, nudge.text, "every placeholder is filled")
    assert_equal 1, @sent.size
    button = @sent.sole[2].find { it[:type] == "actions" }[:elements].first
    assert_equal "come back for stickers", button[:text][:text]
  end

  test "it replaces the bandit's send that day instead of adding one" do
    assert_no_difference -> { @user.nudges.delivered.where(kind: "bandit").count } do
      assert_equal "comeback", deliver.kind
    end
    assert_equal 1, @user.nudges.delivered.where("sent_at >= ?", at_slot.beginning_of_day).count
    assert_nil deliver(at_slot + 5.minutes), "nothing more that day"
    assert_equal 1, @sent.size
  end

  test "once for each missed day" do
    first = deliver
    assert_nil Nudge::Fixed.comeback(Nudge::Context.new(@user.reload, at_slot + 6.hours)), "this missed day has its DM"

    second = deliver(at_slot(10))
    assert_equal [ "comeback", at_slot(10).to_date - 1 ], [ second.kind, second.built_on ], "another day missed is another DM"
    assert_not_equal first.built_on, second.built_on
  end

  test "not for someone who has never built, who the setup nudges are for" do
    Hackatime.stubbed_spans = {}
    @user.streak_activities.delete_all

    assert_equal "bandit", deliver.kind
  end

  test "not for someone who built yesterday, or has built today" do
    built_on(7, 8)
    assert_not_equal "comeback", deliver.kind

    @user.nudges.where.not(kind: "milestone").delete_all
    @user.update_columns(slack_dmed_at: nil)
    built_on(7, 9)
    assert_nil deliver(at_slot(9, hour: 19, min: 10)), "built today already, so there's no reason to nudge"
  end

  test "a weekend builder gets it on a Sunday after missing Saturday, at their weekend slot" do
    @user.project.update!(build_time: "weekends")
    built_on(6)

    nudge = deliver(at_slot(8, hour: 11, min: 5))

    assert_equal [ "comeback", at_slot(7).to_date ], [ nudge.kind, nudge.built_on ]
  end

  test "at the cap of 3 packs it still goes out, but doesn't promise stickers" do
    @user.rewards.create!(key: "stickers")
    earn_packs(2)

    nudge = deliver

    assert_equal [ "comeback", "comeback", false ], [ nudge.kind, nudge.arm, nudge.stickers_promised ]
    assert_no_match(/sticker/i, nudge.text)
  end

  test "an account that can't have stickers isn't promised them" do
    @user.update_columns(hackatime_trust_level: "red")

    assert_equal [ "comeback", false ], deliver.then { [ it.arm, it.stickers_promised ] }
  end

  test "coding 5 minutes within 24 hours of the DM earns a pack, once, and tells them" do
    nudge = deliver
    built_on(7)
    Hackatime.stubbed_spans["1001"] << span(at_slot(10, hour: 12), 5) # 16 hours on

    travel_to(at_slot(10, hour: 13)) { Reward.award_comeback_stickers!(@user.reload) }

    assert_equal %w[comeback_stickers_1], @user.rewards.pluck(:key)
    assert_equal at_slot(10, hour: 13), nudge.reload.stickers_earned_at
    assert_equal "YAYY!!! You came back and worked on your game! Where should we send them??",
                 enqueued_jobs.find { it[:job] == SlackMessageJob }[:args].second

    travel_to(at_slot(10, hour: 14)) { Reward.award_comeback_stickers!(@user.reload) }
    assert_equal 1, @user.rewards.count, "the same DM doesn't earn another"
  end

  test "4 minutes is not enough, and time after the 24 hours doesn't count" do
    deliver
    built_on(7)
    Hackatime.stubbed_spans["1001"] << span(at_slot(10, hour: 12), 4)
    travel_to(at_slot(10, hour: 13)) { Reward.award_comeback_stickers!(@user.reload) }
    assert_empty @user.rewards

    Hackatime.stubbed_spans["1001"] = [ span(at_slot(10, hour: 19, min: 10), 30) ]
    travel_to(at_slot(10, hour: 20)) { Reward.award_comeback_stickers!(@user.reload) }
    assert_empty @user.rewards, "just over 24 hours after the DM"
  end

  test "a DM that didn't promise stickers earns none" do
    @user.rewards.create!(key: "stickers")
    earn_packs(2)
    nudge = deliver
    built_on(7)
    Hackatime.stubbed_spans["1001"] << span(at_slot(10, hour: 12), 30)

    travel_to(at_slot(10, hour: 13)) { Reward.award_comeback_stickers!(@user.reload) }

    assert_equal 3, Reward.sticker_packs_earned(@user)
    assert_nil nudge.reload.stickers_earned_at
  end

  test "the first-hour stickers count towards the cap of 3" do
    nudge = deliver
    @user.rewards.create!(key: "stickers")
    earn_packs(1)
    built_on(7)
    Hackatime.stubbed_spans["1001"] << span(at_slot(10, hour: 12), 30)

    travel_to(at_slot(10, hour: 13)) { Reward.award_comeback_stickers!(@user.reload) }
    assert_equal 3, Reward.sticker_packs_earned(@user), "that was the third"

    other = @user.nudges.create!(kind: "comeback", arm: "comeback_stickers", stickers_promised: true, built_on: at_slot(10).to_date - 1, delivered: true, sent_at: at_slot(10, hour: 14))
    Hackatime.stubbed_spans["1001"] << span(at_slot(10, hour: 15), 30)
    travel_to(at_slot(10, hour: 16)) { Reward.award_comeback_stickers!(@user.reload) }

    assert_equal 3, Reward.sticker_packs_earned(@user), "no fourth"
    assert_nil other.reload.stickers_earned_at
    assert_not_nil nudge.reload.stickers_earned_at
  end

  test "the cap holds when two syncs earn at the same moment" do
    @user.rewards.create!(key: "stickers")
    earn_packs(1)
    nudges = 2.times.map do |index|
      @user.nudges.create!(kind: "comeback", arm: "comeback_stickers", stickers_promised: true, built_on: at_slot(10).to_date - 1 - index,
                           delivered: true, sent_at: at_slot(10, hour: 10 + index))
    end
    built_on(7)
    Hackatime.stubbed_spans["1001"] << span(at_slot(10, hour: 12), 30)

    travel_to(at_slot(10, hour: 14)) { 2.times { Reward.award_comeback_stickers!(User.find(@user.id)) } }

    assert_equal 3, Reward.sticker_packs_earned(@user)
    assert_equal 1, nudges.count { it.reload.stickers_earned_at }
  end

  test "a comeback nudge is scored on building at all in the 2 hours after it" do
    nudge = deliver
    built_on(7)
    Hackatime.stubbed_spans["1001"] << span(at_slot + 40.minutes, 2)

    travel_to(at_slot + 3.hours) { Nudge.score_due }

    assert_equal 1, nudge.reload.reward
  end

  test "a comeback nudge is not counted by the bandit" do
    deliver
    assert_empty Nudge.bandit
  end
end
