require "test_helper"

# D-113: the bot doesn't reach a banned account, whatever else is true of it. (Nudge::Context's other rules are NudgeTest's.)
class NudgeContextBanTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
    @project = @user.project
    # SlackBot.dm is stubbed, so nothing here is stopped by its own check: it's the nudge side that must not ask it.
    @sent = []
    sent = @sent
    @dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil| sent << [ slack_id, text, blocks ] && SlackMessage.new("D0ORPHEUS", "1.0") }
  end

  teardown { SlackBot.define_singleton_method(:dm, @dm) }

  # Noon in New York on Oct 26, inside the program and outside quiet hours.
  def noon = Time.find_zone("America/New_York").local(2026, 10, 26, 12)

  def ban!(user = @user) = user.ban!("Fraud.", by: users(:ana))

  def new_ship(hours)
    @project.ships.new(title: "v1", description: "x" * 50, repo_url: "https://github.com/a/b", demo_url: "https://a.itch.io/b", hours:, status: "awaiting_fraud").tap { |ship| ship.save!(validate: false) }
  end

  # The fraud check passes: the ship is approved, as Ship#pass_fraud! leaves it.
  def approve!(ship)
    ship.assign_attributes(approved_columns(ship.hours))
    ship.save!(validate: false)
    ship
  end

  test "the bot reaches someone on Slack who isn't banned, and not once they are" do
    assert Nudge::Context.new(@user, noon).reachable?

    ban!
    assert_not Nudge::Context.new(@user, noon).reachable?
  end

  test "no nudge is due to a banned account" do
    assert Nudge::Context.new(@user, noon).may_nudge?

    ban!
    assert_not Nudge::Context.new(@user.reload, noon).may_nudge?
  end

  test "no approval DM is created for a banned account, and the same ship's is for anyone else" do
    ship = approve!(new_ship(2.5))
    ban!

    travel_to(noon) do
      assert_nil Nudge::Approved.deliver(ship, noon)
      assert_empty @sent
      assert_equal 0, @user.nudges.count

      @user.update!(banned_at: nil, ban_reason: nil)
      assert Nudge::Approved.deliver(ship, noon).delivered
    end
    assert_equal [ "U0ORPHEUS" ], @sent.map(&:first)
  end
end
