require "test_helper"

class NudgePledgeTest < ActiveSupport::TestCase
  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @user = users(:ana)
    @user.project.destroy!
    @user.update!(timezone: "America/New_York", created_at: at_slot - 2.days)

    @sent = []
    sent = @sent
    @dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil| sent << [ slack_id, text, blocks ] && SlackMessage.new("D0ANA", "1.0") }
  end

  teardown do
    SlackBot.define_singleton_method(:dm, @dm)
    Rails.configuration.x.admin_slack_ids = @admins
  end

  # 7:05pm in New York on Oct 24, a program day.
  def at_slot(day = 24, hour: 19, min: 5)
    Time.find_zone("America/New_York").local(2026, 10, day, hour, min)
  end

  def deliver(at = at_slot)
    travel_to(at) { Nudge.deliver_pledge_nudges(at) }
  end

  def new_project
    Project.create!(user: @user, idea: "pong", prize_key: "u2c", pace_minutes: 20, build_time: "evening", signed_on: Date.new(2026, 10, 24))
    @user.reload
  end

  def pledge_nudges = Nudge.where(arm: Nudge::PLEDGE_ARM)

  test "someone with no project gets the fixed pledge DM at the evening slot, as a tracked setup nudge" do
    deliver

    nudge = pledge_nudges.sole
    assert_equal [ "setup", "pledge_setup", users(:ana), true, 1.0 ], [ nudge.kind, nudge.arm, nudge.user, nudge.delivered, nudge.propensity ]
    assert_equal "U0ANA", @sent.sole.first
    assert_equal Nudge::Copy::FIXED["pledge_setup"].sole, nudge.text
    assert nudge.token.present?
    buttons = @sent.sole.third.find { |block| block[:type] == "actions" }[:elements]
    assert_equal [ nudge.link_url, nudge.stop_url ], buttons.map { |button| button[:url] }
    assert_equal "pledge your game", buttons.first[:text][:text]
    assert_equal "#{Rails.configuration.x.app_url}/start", nudge.destination_url
  end

  test "it has a gif like the other fixed nudges" do
    assert_equal "nudge.pledge_setup", "nudge.#{Nudge::PLEDGE_ARM}"
    assert SlackGifs.block("nudge.pledge_setup", force: true)
    assert_equal "image", Nudge::Message.new(pledge_nudges.first || @user.nudges.new(arm: "pledge_setup", text: "x"), gifs: true).blocks.second[:type]
  end

  test "the bandit's pledge arm is a different arm" do
    assert_not_equal "pledge", Nudge::PLEDGE_ARM
    assert_not Nudge::Copy::ARMS.key?(Nudge::PLEDGE_ARM)
    assert_not Nudge::Copy::FIXED.key?("pledge")
  end

  test "someone with a project is left out" do
    Rails.configuration.x.admin_slack_ids = []
    users(:orpheus).update!(timezone: "America/New_York", created_at: at_slot - 2.days)

    assert_equal [ @user ], Nudge.pledge_candidates(at_slot).to_a
    new_project
    assert_empty Nudge.pledge_candidates(at_slot)
    deliver
    assert_empty @sent
  end

  test "admins are left out" do
    Rails.configuration.x.admin_slack_ids = [ "U0ANA" ]
    deliver
    assert_empty @sent
    assert_not_includes Nudge.pledge_candidates(at_slot), @user
  end

  test "muted, no Slack, no timezone are left out" do
    @user.update!(slack_muted_at: at_slot - 1.day)
    assert_not_includes Nudge.pledge_candidates(at_slot), @user

    @user.update!(slack_muted_at: nil, timezone: nil)
    assert_not_includes Nudge.pledge_candidates(at_slot), @user

    @user.update!(timezone: "America/New_York", slack_id: "")
    assert_not_includes Nudge.pledge_candidates(at_slot), @user
  end

  test "a failed DM is skipped for a day, then tried again" do
    @user.update!(slack_dm_failed_at: at_slot - 1.hour, slack_dm_error: "user_disabled")
    deliver
    assert_empty @sent

    @user.update!(slack_dm_failed_at: at_slot - Nudge::DM_RETRY_AFTER - 1.minute)
    deliver
    assert_equal 1, @sent.size
  end

  test "someone who signed up less than 3 hours before the slot waits" do
    @user.update!(created_at: at_slot(hour: 19, min: 0) - 3.hours + 1.minute)
    deliver
    assert_empty @sent

    @user.update!(created_at: at_slot(hour: 19, min: 0) - 3.hours)
    deliver
    assert_equal 1, @sent.size
  end

  test "it only goes in the 15 minutes after 7pm their time" do
    deliver(at_slot(hour: 18, min: 59))
    deliver(at_slot(hour: 19, min: 15))
    deliver(at_slot(hour: 12, min: 0))
    assert_empty @sent

    deliver(at_slot(hour: 19, min: 0))
    assert_equal 1, @sent.size
  end

  test "the slot is in their timezone" do
    @user.update!(timezone: "Australia/Sydney")
    deliver(Time.find_zone("Australia/Sydney").local(2026, 10, 25, 19, 3))
    assert_equal 1, @sent.size
  end

  test "it only goes while the program runs" do
    deliver(at_slot(22))
    deliver(Time.find_zone("America/New_York").local(2026, 11, 3, 19, 5))
    assert_empty @sent
  end

  test "it repeats no more often than SETUP_EVERY" do
    deliver(at_slot(24))
    assert_equal 1, @sent.size

    deliver(at_slot(24 + 2))
    assert_equal 1, @sent.size, "2 days later is too soon"

    deliver(at_slot(24 + 3, min: 6))
    assert_equal 2, @sent.size
  end

  test "an undelivered one doesn't hold up the next try" do
    @user.nudges.create!(kind: "setup", arm: "pledge_setup", delivered: false, sent_at: at_slot - 1.hour)
    deliver
    assert_equal 1, @sent.size
  end

  test "nothing goes within a message gap of another DM" do
    @user.update!(slack_dmed_at: at_slot - 30.minutes)
    deliver
    assert_empty @sent
  end

  test "it counts as done once they have a project" do
    nudge = @user.nudges.create!(kind: "setup", arm: "pledge_setup", delivered: true, sent_at: at_slot)
    assert_not nudge.reload.step_done?
    new_project
    assert nudge.reload.step_done?
  end

  test "deliver_due still ignores people with no project, and the job runs both" do
    users(:orpheus).update!(timezone: "America/New_York")
    Rails.configuration.x.admin_slack_ids = []
    reached = []
    original = Nudge.method(:deliver_to)
    Nudge.define_singleton_method(:deliver_to) { |user, _now = nil| reached << user }
    travel_to(at_slot) { Nudge.deliver_due(at_slot) }
    assert_not_includes reached, @user
    assert_includes reached, users(:orpheus)
  ensure
    Nudge.define_singleton_method(:deliver_to, original)
  end

  test "NudgeDeliveryJob calls both entry points" do
    calls = []
    due = Nudge.method(:deliver_due)
    pledge = Nudge.method(:deliver_pledge_nudges)
    Nudge.define_singleton_method(:deliver_due) { |*| calls << :due }
    Nudge.define_singleton_method(:deliver_pledge_nudges) { |*| calls << :pledge }
    NudgeDeliveryJob.perform_now
    assert_equal [ :due, :pledge ], calls
  ensure
    Nudge.define_singleton_method(:deliver_due, due)
    Nudge.define_singleton_method(:deliver_pledge_nudges, pledge)
  end
end
