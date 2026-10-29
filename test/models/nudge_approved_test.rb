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

  # An approved ship whose review left this message for the participant (D-112), as review_feedback.
  def approve_with_message!(message, hours = 2.5)
    ship = new_ship(hours)
    ship.review_feedback = message
    approve!(ship)
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

  # D-112: the reviewer's message to the participant goes after the usual line.

  test "a message from the reviewer follows the usual line, after a lead-in, as a quote" do
    nudge = deliver(approve_with_message!("Loved the boss fight! The music gave me chills :yay:"))
    slack_id, text, blocks = @sent.sole

    assert nudge.delivered
    usual, note = text.split("\n\n")
    assert_includes usual, "2.5"
    assert_includes usual, @goal.name
    assert_equal "your reviewer left you a note:\n> Loved the boss fight! The music gave me chills :yay:", note
    assert_equal "U0ORPHEUS", slack_id
    # What is kept is what Slack got: the nudge's text, the message's fallback text and the section block are one string.
    assert_equal text, nudge.reload.text
    assert_equal text, blocks.first.dig(:text, :text)
    assert_equal text, Nudge::Message.new(nudge).blocks.first.dig(:text, :text)
  end

  test "with no message from the reviewer the DM is the usual line alone" do
    [ nil, "", " \r\n \t " ].each do |blank|
      @user.update_column(:slack_dmed_at, nil)
      assert deliver(approve_with_message!(blank)).delivered
      assert_not_includes @sent.last.second, "\n", "nothing is added for #{blank.inspect}"
      assert_not_includes @sent.last.second, Nudge::Copy::REVIEWER_NOTE_LEAD_IN
    end
    assert_equal 3, @sent.size
  end

  test "the message is escaped for Slack, and keeps emoji codes, bold text and a percent sign" do
    deliver(approve_with_message!("<!channel> & <https://x.example|click> 100% *proud* :yay: >nope"))

    assert_equal "> &lt;!channel&gt; &amp; &lt;https://x.example|click&gt; 100% *proud* :yay: &gt;nope", @sent.sole.second.lines(chomp: true).last
  end

  test "every line of a message is quoted, a blank one too, whatever breaks the lines" do
    deliver(approve_with_message!("one\r\n\r\n\r\n\r\ntwo\nthree  \n> four"))

    assert_equal [ "your reviewer left you a note:", "> one", ">", "> two", "> three", "> &gt; four" ], @sent.sole.second.lines(chomp: true).last(6)
  end

  test "a very long message is cut so that Slack takes the DM, and a cut never splits an escape" do
    deliver(approve_with_message!("&" * 3000))
    text = @sent.sole.second

    assert_operator text.length, :<, 3000, "a section is at most 3000 characters"
    assert_match(/\n> (&amp;)+…\z/, text)
    assert_includes text, "approved"
  end

  test "a message is read when the DM goes, so a DM held for the morning carries it" do
    ship = approve_with_message!("See you tomorrow!")
    late = zone.local(2026, 10, 25, 23)
    assert_equal zone.local(2026, 10, 26, 8), deliver(ship, late)
    assert_empty @sent

    ship.update_column(:review_feedback, "See you tomorrow! I fixed a typo.")
    assert deliver(ship, zone.local(2026, 10, 26, 8)).delivered
    assert_equal "> See you tomorrow! I fixed a typo.", @sent.sole.second.lines(chomp: true).last
  end

  test "every approved arm has copy, a button and a GIF" do
    %w[approved_short approved_reached approved_no_goal].each do |arm|
      assert Nudge::Copy::FIXED.key?(arm)
      assert Nudge::Copy::LINKS.key?(arm)
      assert SlackGifs::GIFS.key?("nudge.#{arm}")
    end
  end
end
