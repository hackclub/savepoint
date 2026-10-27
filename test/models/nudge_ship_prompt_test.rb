require "test_helper"

# D-096: the bot asks someone to ship at 5 unshipped hours.
class NudgeShipPromptTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
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

  def zone = Time.find_zone("America/New_York")

  # Oct 25 at 8pm in New York.
  def now = zone.local(2026, 10, 25, 20)

  def build!(hours, at: now)
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(zone.local(2026, 10, 24, 10), (hours * 60).to_i) ] }
    travel_to(at) { StreakActivity.sync_for_user!(@user.reload) }
  end

  def ship!(status, hours, at: now)
    travel_to(at) do
      @user.project.ships.new(title: "v1", description: "x" * 50, repo_url: "https://github.com/a/b", demo_url: "https://a.itch.io/b", hours:, status:).save!(validate: false)
    end
  end

  def deliver(at = now)
    travel_to(at) { Nudge::ShipPrompt.deliver(@user.reload, at) }
  end

  def vars = Nudge::ShipPrompt.vars(Nudge::Context.new(@user.reload, now))

  test "it sends once at 5 hours, with a button to the ship page, and not again for the same crossing" do
    build!(5.5)
    nudge = deliver
    assert nudge.delivered
    assert_equal "ship_prompt", nudge.kind
    assert_equal 1, @sent.size
    assert_match "5.5", @sent.first.second
    assert_equal "/project/ship", nudge.destination_url.delete_prefix(Rails.configuration.x.app_url)
    assert_nil deliver(now + 3.hours)
    assert_equal 1, @sent.size
  end

  test "it does not send below 5 hours" do
    build!(4.5)
    assert_nil deliver
    assert_empty @sent
  end

  test "after a ship the next crossing sends again" do
    build!(5.5)
    deliver
    ship!("in_review", 5.5, at: now + 10.minutes)
    build!(9, at: now + 20.minutes)
    assert_nil deliver(now + 70.minutes)
    build!(10.8, at: now + 80.minutes)
    assert deliver(now + 85.minutes).delivered
    assert_equal 2, @sent.size
  end

  test "a rejected ship does not re-arm it" do
    build!(5.5)
    deliver
    ship!("rejected", 5.5, at: now + 1.hour)
    assert_nil deliver(now + 3.hours)
  end

  test "a muted participant gets nothing" do
    build!(5.5)
    @user.update!(slack_muted_at: Time.current)
    assert_nil deliver
    assert_empty @sent
  end

  test "an admin gets nothing" do
    before = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ @user.slack_id ]
    build!(5.5)
    assert_nil deliver
    assert_empty @sent
  ensure
    Rails.configuration.x.admin_slack_ids = before
  end

  test "nothing goes after the program ends" do
    build!(5.5)
    assert_nil deliver(Program::ENDS_AT + 1.hour)
    assert_empty @sent
  end

  test "nothing goes within the message gap of another DM, or in quiet hours" do
    build!(5.5)
    @user.update_column(:slack_dmed_at, now - 10.minutes)
    assert_nil deliver
    assert_nil deliver(zone.local(2026, 10, 25, 23))
    assert_empty @sent
    assert deliver(now + 70.minutes).delivered
  end

  test "before a first ship no variant says since your last ship" do
    build!(5.5)
    assert_equal "and haven't shipped yet", vars[:since]
    Nudge::Copy.variants_for("ship_prompt").each do |variant|
      assert_no_match(/last ship/, format(variant, **vars))
    end
  end

  test "after a ship the last variant says since your last ship" do
    ship!("approved", 1)
    build!(6.5)
    assert_equal "since your last ship", vars[:since]
    assert_match(/\Ayou've built 5.5 hours of .+ since your last ship\. time to ship it! :yay:\z/, format(Nudge::Copy.variants_for("ship_prompt").last, **vars))
  end

  test "a sync past 5 hours queues the DM, and one below it does not" do
    assert_no_enqueued_jobs(only: NudgeShipPromptJob) { build!(3) }
    assert_enqueued_with(job: NudgeShipPromptJob, args: [ @user.id ]) { build!(5.5) }
  end

  test "a sync after the program ends queues nothing" do
    assert_no_enqueued_jobs(only: NudgeShipPromptJob) { build!(5.5, at: Program::ENDS_AT + 1.hour) }
  end

  test "a ship prompt is scored on whether they shipped after it" do
    build!(5.5)
    nudge = deliver
    nudge.score!
    assert_equal 0, nudge.reward
    ship!("in_review", 5.5, at: now + 1.hour)
    nudge.score!
    assert_equal 1, nudge.reward
  end
end
