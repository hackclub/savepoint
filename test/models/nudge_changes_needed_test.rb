require "test_helper"

# D-139: Changes needed gives the participant a window to ship again, and a DM that says until when.
class NudgeChangesNeededTest < ActiveSupport::TestCase
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

  test "changes needed sends one DM with the deadline in their time zone and the reviewer's note" do
    travel_to(Program::ENDS_AT - 6.hours) do # 5:59pm in New York
      assert_enqueued_with(job: NudgeChangesNeededJob, args: [ @ship.id ]) do
        @ship.decide!("changes_needed", by: @reviewer, feedback: "Add a screenshot of the game.")
      end
      perform_enqueued_jobs
      NudgeChangesNeededJob.perform_now(@ship.id)
      @ship.update!(review_feedback: "Changed.")
      perform_enqueued_jobs
    end

    text = texts.sole
    assert_includes text, "needs a few changes before it can be approved"
    assert_includes text, "*#{@project.title}*"
    # The cutoff (the deadline plus grace, end of day in New York) runs later than 24 hours, so it is the deadline.
    assert_includes text, "you have until Wed Nov 4, 11:59 pm to fix it and ship again."
    assert_includes text, "your reviewer left you a note:\n> Add a screenshot of the game."
    assert_equal [ "changes_needed" ], @user.nudges.delivered.pluck(:kind)
    assert_equal "open your project", @sent.first.third.find { it[:type] == "actions" }[:elements].first[:text][:text]
  end

  test "past the cutoff the DM names 24 hours after the verdict" do
    verdict = @project.reload.ship_cutoff - 6.hours
    travel_to(verdict) { @ship.decide!("changes_needed", by: @reviewer, feedback: "Fix the build.") }
    travel_to(verdict + 5.minutes) { perform_enqueued_jobs }

    assert_includes texts.sole, "you have until Thu Nov 5, 5:59 pm to"
  end

  test "no DM for someone who stopped the bot" do
    @user.update!(slack_muted_at: Time.current)
    @ship.decide!("changes_needed", by: @reviewer, feedback: "Fix it.")
    perform_enqueued_jobs
    assert_empty @sent
  end

  test "in quiet hours the DM waits for the morning" do
    travel_to(Time.find_zone("America/New_York").local(2026, 10, 25, 23)) do
      @ship.update_columns(status: "changes_needed", reviewed_at: Time.current)
      NudgeChangesNeededJob.perform_now(@ship.id)
      assert_empty @sent
      assert_enqueued_with(job: NudgeChangesNeededJob, args: [ @ship.id ], at: Time.find_zone("America/New_York").local(2026, 10, 26, 8))
    end
  end

  test "approve and reject send no changes needed DM" do
    assert_no_enqueued_jobs(only: NudgeChangesNeededJob) do
      @ship.decide!("rejected", by: @reviewer, judgement: "Copied.")
    end
    @ship.update_columns(status: "in_review")
    assert_no_enqueued_jobs(only: NudgeChangesNeededJob) do
      @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", judgement: "Solid.", feedback: "Nice.")
    end
  end

  test "the window: 24 hours after the verdict or the normal cutoff, whichever is later" do
    cutoff = @project.ship_cutoff
    assert_nil @project.changes_needed_until

    travel_to(Program::ENDS_AT - 1.hour) { @ship.decide!("changes_needed", by: @reviewer, feedback: "Fix it.") }
    @project.reload
    assert_equal cutoff.to_i, @project.changes_needed_until.to_i, "the cutoff is later than 24 hours from the verdict"
    assert @project.may_ship?(now: cutoff - 1.minute)

    @ship.update_columns(reviewed_at: cutoff - 1.hour)
    @project.reload
    assert_equal (cutoff + 23.hours).to_i, @project.changes_needed_until.to_i
    assert @project.may_ship?(now: cutoff + 22.hours)
    assert_not @project.may_ship?(now: cutoff + 23.hours + 1.second)
  end

  test "others are refused after their cutoff" do
    assert_not @project.may_ship?(now: @project.ship_cutoff + 1.second)
    assert @project.may_ship?(now: @project.ship_cutoff)
  end

  test "a later changes needed sets a new window, and a later approval or rejection ends it" do
    cutoff = @project.ship_cutoff
    @ship.update_columns(status: "changes_needed", reviewed_at: cutoff - 1.hour)
    second = ship_now
    second.update_columns(status: "changes_needed", reviewed_at: cutoff + 2.hours)
    assert_equal (cutoff + 26.hours).to_i, @project.reload.changes_needed_until.to_i

    third = ship_now
    third.update_columns(status: "awaiting_fraud", reviewed_at: cutoff + 3.hours)
    assert_nil @project.reload.changes_needed_until
    assert_not @project.may_ship?(now: cutoff + 4.hours)

    third.update_columns(status: "rejected", reviewed_at: cutoff + 3.hours)
    assert_nil @project.reload.changes_needed_until
  end

  test "hours logged after the end still count, so a ship in the window carries them" do
    travel_to(Program::ENDS_AT + 3.hours) do
      @user.streak_activities.create!(activity_date: Program::ENDS_AT.to_date, coded_seconds: 2 * 3600)
      assert_equal 12.0, @project.reload.hours_logged(refresh: false)
    end
  end

  test "the ship form is open in the window and closed after it" do
    cutoff = @project.ship_cutoff
    @ship.update_columns(status: "changes_needed", reviewed_at: cutoff - 1.hour)
    assert @project.reload.may_ship?(now: cutoff + 10.hours)
    assert_not @project.may_ship?(now: cutoff + 24.hours)
  end

  private
    def ship_now
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours: 10, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
end
