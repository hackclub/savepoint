require "test_helper"

# D-098: the bot's DM when a ship is approved, as progress toward the goal.
class NudgeApprovedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
    @project = @user.project
    @goal = @project.chosen_prize
    @sent = []
    sent = @sent
    @dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil| sent << [ slack_id, text, blocks ] && SlackMessage.new("D0ORPHEUS", "1.0") }
    @admins = Rails.configuration.x.admin_slack_ids
  end

  teardown do
    SlackBot.define_singleton_method(:dm, @dm)
    Rails.configuration.x.admin_slack_ids = @admins
  end

  def zone = Time.find_zone("America/New_York")

  # Noon in New York on Oct 25, inside the program and outside quiet hours.
  def noon = zone.local(2026, 10, 25, 12)

  def new_ship(hours)
    @project.ships.new(title: "v1", description: "x" * 50, repo_url: "https://github.com/a/b", demo_url: "https://a.itch.io/b", hours:, status: "awaiting_fraud").tap { |ship| ship.save!(validate: false) }
  end

  # The fraud check passes: the ship is approved with these hours, as Ship#pass_fraud! does.
  def approve!(ship, hours = ship.hours)
    ship.assign_attributes(approved_columns(hours))
    ship.save!(validate: false)
    ship
  end

  def deliver(ship, at = noon)
    travel_to(at) { Nudge::Approved.deliver(ship, at) }
  end

  test "approving a ship queues the DM, and saving it again does not" do
    ship = new_ship(2)
    assert_enqueued_with(job: NudgeApprovedJob, args: [ ship.id ]) { approve!(ship) }
    assert_no_enqueued_jobs { ship.assign_attributes(title: "v1.1", approved_hours: 1.5) && ship.save!(validate: false) }
    assert_no_enqueued_jobs { ship.touch }
  end

  test "short of the goal it says what the ship added, the total, the goal and the hours still needed" do
    ship = approve!(new_ship(2.5))
    nudge = deliver(ship)

    assert nudge.delivered
    assert_equal [ "approved", "approved_short" ], [ nudge.kind, nudge.arm ]
    still = (@goal.hours - 2.5).round(1)
    text = @sent.sole.second
    assert_includes text, "2.5"
    assert_includes text, @goal.name
    assert_includes text, ApplicationController.helpers.project_hours(still)
    assert_equal "see the shop", Nudge::Copy.link_for(nudge.arm).first
    assert_equal "/shop", nudge.destination_url.delete_prefix(Rails.configuration.x.app_url)
  end

  test "a second ship says only what it added on top of the first" do
    approve!(new_ship(2))
    ship = approve!(new_ship(3.5))
    vars = Nudge::Approved.vars(ship)
    assert_equal [ "1.5", "3.5" ], [ vars[:added], vars[:approved] ]
  end

  test "a ship that adds nothing leaves the added hours out, and still sends" do
    approve!(new_ship(4))
    ship = approve!(new_ship(3))
    assert_not Nudge::Approved.vars(ship).key?(:added)
    nudge = deliver(ship)
    assert nudge.delivered
    assert_not_includes @sent.sole.second, "added"
  end

  test "covering the goal says so and links the shop to claim it" do
    ship = approve!(new_ship(@goal.hours + 1))
    nudge = deliver(ship)

    assert_equal "approved_reached", nudge.arm
    assert_includes @sent.sole.second, @goal.name
    assert_equal [ "claim your prize", :shop ], Nudge::Copy.link_for(nudge.arm)
  end

  test "with no goal it gives the approved total and the shop" do
    @project.update_column(:prize_key, nil)
    ship = approve!(new_ship(6.5))
    nudge = deliver(ship)

    assert_equal "approved_no_goal", nudge.arm
    assert_includes @sent.sole.second, "6.5"
    assert_equal [ "open the shop", :shop ], Nudge::Copy.link_for(nudge.arm)
  end

  test "the message has the shop button, the stop button and a GIF from the celebration pool" do
    ship = approve!(new_ship(2.5))
    nudge = deliver(ship)
    blocks = Nudge::Message.new(nudge, gifs: true).blocks

    assert_equal [ "see the shop", "stop these messages" ], blocks.last[:elements].map { |button| button[:text][:text] }
    assert_equal nudge.link_url, blocks.last[:elements].first[:url]
    assert_includes SlackGifs::GIFS.fetch("nudge.approved_short").map { |gif| gif["url"] }, blocks.second[:image_url]
  end

  test "a muted participant gets nothing" do
    @user.update!(slack_muted_at: Time.current)
    assert_nil deliver(approve!(new_ship(2)))
    assert_empty @sent
  end

  test "an admin gets nothing" do
    Rails.configuration.x.admin_slack_ids = [ @user.slack_id ]
    assert_nil deliver(approve!(new_ship(2)))
    assert_empty @sent
  end

  test "it still sends after the program ends" do
    nudge = deliver(approve!(new_ship(2)), Program::ENDS_AT + 3.days + 16.hours)
    assert nudge.delivered
    assert_equal 1, @sent.size
  end

  test "one DM for each ship, however often it is delivered" do
    ship = approve!(new_ship(2))
    assert deliver(ship).delivered
    assert_nil deliver(ship, noon + 3.hours)
    assert_equal 1, @sent.size
    assert_equal 1, @user.nudges.where(kind: "approved", ship_id: ship.id).count
  end

  test "a ship that is not approved gets nothing" do
    assert_nil deliver(new_ship(2))
    assert_empty @sent
  end

  test "in quiet hours it waits until the morning, and the job sends it then" do
    ship = approve!(new_ship(2))
    late = zone.local(2026, 10, 25, 23)
    morning = zone.local(2026, 10, 26, 8)

    assert_equal morning, deliver(ship, late)
    assert_empty @sent

    travel_to(late) do
      clear_enqueued_jobs
      NudgeApprovedJob.perform_now(ship.id)
      assert_enqueued_with(job: NudgeApprovedJob, args: [ ship.id ], at: morning)
    end
    assert deliver(ship, morning).delivered
  end

  test "right after another DM it waits out the message gap" do
    ship = approve!(new_ship(2))
    @user.update_column(:slack_dmed_at, noon - 10.minutes)

    assert_in_delta noon + 50.minutes, deliver(ship), 1
    assert_empty @sent
    assert deliver(ship, noon + 51.minutes).delivered
  end

  test "every approved arm has copy, a button and a GIF" do
    %w[approved_short approved_reached approved_no_goal].each do |arm|
      assert Nudge::Copy::FIXED.key?(arm)
      assert Nudge::Copy::LINKS.key?(arm)
      assert SlackGifs::GIFS.key?("nudge.#{arm}")
    end
  end
end
