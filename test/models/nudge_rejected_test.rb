require "test_helper"

# D-137: the bot DMs a participant when a ship is rejected for good, and when they are banned. A banned account gets nothing else (D-113).
class NudgeRejectedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @project = projects(:orpheus)
    @user = @project.user
    @user.update!(timezone: "America/New_York")
    link_hackatime(@user)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
    @reviewer = users(:ana)
    travel_to(Program::STARTS_AT + 2.days) # 5pm in New York: outside quiet hours
    @user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
    @ship = ship_now
    @ship.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)

    @sent = []
    sent = @sent
    @dm = SlackBot.method(:dm)
    # Stands in for Slack, with the ban check of the real one: a banned account's DM goes only with allow_banned.
    SlackBot.define_singleton_method(:dm) do |slack_id, text:, blocks:, on_error: nil, allow_banned: false|
      next if !allow_banned && banned_recipient?(slack_id)
      sent << [ slack_id, text, blocks ]
      SlackMessage.new("D0ORPHEUS", "1.0")
    end
  end

  teardown { SlackBot.define_singleton_method(:dm, @dm) }

  def texts = @sent.map { it.second }

  test "a reject sends one DM with the reviewer's note, not the judgement" do
    assert_enqueued_with(job: NudgeRejectedJob, args: [ @ship.id ]) do
      assert @ship.decide!("rejected", by: @reviewer, judgement: "Template with a new title, 80% copied.", feedback: "This is not your own game.")
    end
    perform_enqueued_jobs

    text = texts.sole
    assert_includes text, "was rejected"
    assert_includes text, "can't be shipped again"
    assert_includes text, "DM Armand"
    assert_includes text, "*#{@project.title}*"
    assert_includes text, "> This is not your own game."
    assert_not_includes text, "Template with a new title"
    assert_equal [ "rejected" ], @user.nudges.delivered.pluck(:kind)
  end

  test "a reject with no note sends the DM without one" do
    @ship.decide!("rejected", by: @reviewer, judgement: "Copied.")
    perform_enqueued_jobs

    assert_not_includes texts.sole, "note"
  end

  test "a repeat reject, a replayed job or saving the ship again sends nothing more" do
    @ship.decide!("rejected", by: @reviewer, judgement: "Copied.", feedback: "No.")
    perform_enqueued_jobs
    assert_no_enqueued_jobs { @ship.reload.touch }
    NudgeRejectedJob.perform_now(@ship.id)
    @ship.update!(review_feedback: "Changed.")
    perform_enqueued_jobs

    assert_equal 1, @sent.size
  end

  test "changes needed and approve are unchanged: no rejection DM" do
    assert_no_enqueued_jobs(only: NudgeRejectedJob) do
      @ship.decide!("changes_needed", by: @reviewer, feedback: "Add a screenshot.")
    end
    @ship.update_columns(status: "in_review")
    assert_no_enqueued_jobs(only: NudgeRejectedJob) do
      @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", judgement: "Solid.", feedback: "Nice.")
    end
    assert_empty @sent
  end

  test "in quiet hours the rejection DM waits for the morning" do
    travel_to(Time.find_zone("America/New_York").local(2026, 10, 25, 23)) do
      @ship.update_columns(status: "rejected")
      NudgeRejectedJob.perform_now(@ship.id)
      assert_empty @sent
      assert_enqueued_with(job: NudgeRejectedJob, args: [ @ship.id ], at: Time.find_zone("America/New_York").local(2026, 10, 26, 8))
    end
  end

  test "a ban sends exactly one ban DM and no rejection DMs, even for the ships it rejects" do
    other = ship_now
    assert_enqueued_with(job: NudgeBannedJob, args: [ @user.id ]) do
      assert @ship.decide!("banned", by: @reviewer, evidence: "The hours are another person's.")
    end
    assert_no_enqueued_jobs(only: NudgeRejectedJob)
    assert other.reload.rejected?
    perform_enqueued_jobs

    text = texts.sole
    assert_equal "your account was banned from Save Point after review. if you think that's a mistake, DM Armand.", text
    assert_not_includes text, "fraud"
    assert_not_includes text, "hours are another"
    assert_equal [ "banned" ], @user.nudges.delivered.pluck(:kind)
    assert_empty @sent.first.third.select { it[:type] == "actions" }, "no buttons"
  end

  test "the ban DM goes once, even if the job runs again" do
    @ship.decide!("banned", by: @reviewer, evidence: "Fraud.")
    perform_enqueued_jobs
    NudgeBannedJob.perform_now(@user.id)
    perform_enqueued_jobs

    assert_equal 1, @sent.size
  end

  test "every other DM to a banned account stays blocked" do
    @ship.decide!("banned", by: @reviewer, evidence: "Fraud.")
    perform_enqueued_jobs
    @sent.clear

    assert_nil SlackBot.dm(@user.slack_id, text: "hi", blocks: [])
    assert_not Nudge::Context.new(@user.reload).reachable?
    assert_nil Nudge::Rejected.send_for(@ship.id)
    assert_nil Nudge::Banned.deliver(@user), "its own DM went already"
    SlackMessageJob.perform_now(@user.slack_id, "a reward")
    assert_empty @sent
  end

  test "a ban of an account that stopped the bot sends no ban DM" do
    @user.update!(slack_muted_at: Time.current)
    @user.ban!("Fraud.", by: @reviewer)
    perform_enqueued_jobs
    assert_empty @sent
  end

  test "the backfill method sends the rejection DM for a ship id, once" do
    @ship.update_columns(status: "rejected", review_feedback: "Not your game.")
    assert_no_enqueued_jobs { assert @ship.reload.rejected? }

    assert Nudge::Rejected.send_for(@ship.id).delivered
    assert_includes texts.sole, "> Not your game."
    assert_nil Nudge::Rejected.send_for(@ship.id)
  end

  private
    def ship_now
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours: 10, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
end
