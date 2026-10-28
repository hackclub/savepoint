require "test_helper"

class NudgeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(7, hour: 17), 90) ] } # 1.5 hours, on day two

    @sent = []
    sent = @sent
    @dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil| sent << [ slack_id, text, blocks ] && SlackMessage.new("D0ORPHEUS", "1.0") }
  end

  teardown do
    SlackBot.define_singleton_method(:dm, @dm)
    Hackatime.stubbed_spans = {}
  end

  # Orpheus builds in the evening: 7pm in New York. `day` counts from 1 on Oct 17, so day 6 is Oct 23, Save Point's first date.
  def at_slot(day = 8, hour: 19, min: 5)
    Time.find_zone("America/New_York").local(2026, 10, 1, hour, min) + (day + 16).days
  end

  def deliver(at = at_slot)
    travel_to(at) { Nudge.deliver_to(@user.reload, at) }
  end

  def sent!(arm, kind: "bandit", at: at_slot(7))
    @user.nudges.create!(kind:, arm:, delivered: true, sent_at: at)
  end

  # The comeback DM for the day before `day`'s slot, already sent, so a test of the bandit isn't answered by one.
  def comeback_sent!(day)
    @user.nudges.create!(kind: "comeback", arm: "comeback", built_on: at_slot(day).to_date - 1, delivered: true, sent_at: at_slot(day - 1))
  end

  def span(at, minutes)
    { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }
  end

  test "Save Point's first day starts with the kickoff" do
    nudge = deliver(at_slot(6))

    assert_equal [ "program", "kickoff" ], [ nudge.kind, nudge.arm ]
    assert nudge.delivered
    assert_equal [ "D0ORPHEUS", "1.0" ], [ nudge.slack_channel, nudge.slack_ts ]
    assert_equal "U0ORPHEUS", @sent.sole.first
  end

  test "the last days go by Save Point's last day" do
    assert_equal "three_days_left", deliver(at_slot(13)).arm, "Oct 30, three days before the Nov 2 end"
    assert_equal "last_day", deliver(at_slot(16)).arm
    assert_nil deliver(at_slot(17)), "Save Point's over for you"
  end

  test "then milestones, then setup steps, before the bandit" do
    assert_equal "first_session", deliver.arm

    sent!("first_session", kind: "milestone")
    @user.project.update!(repo_later: false)
    assert_equal "repo", deliver(at_slot(9)).arm

    comeback_sent!(10) # the repo nudge went on day 9, and the weekly cap is 5
    assert_equal "bandit", deliver(at_slot(10)).kind, "the repo nudge waits a few days before saying it again"
  end

  test "an approval DM the same day blocks neither a setup nudge nor the weekly cap (D-098)" do
    sent!("first_session", kind: "milestone")
    @user.project.update!(repo_later: false)
    5.times { |n| sent!("approved_short", kind: "approved", at: at_slot(8, hour: 9) - n.hours) }

    nudge = deliver(at_slot(8))

    assert_equal [ "setup", "repo" ], [ nudge.kind, nudge.arm ]
  end

  test "an approval DM the same day is not a nudge sent today, so the day's streak saver or bandit nudge may still go" do
    sent!("first_session", kind: "milestone")
    sent!("approved_short", kind: "approved", at: at_slot(8, hour: 9))
    context = Nudge::Context.new(@user.reload, at_slot(8))
    assert_empty context.sent_today
    assert context.may_nudge?
  end

  test "with time on hackatime and no project picked, the bot asks you to pick one" do
    sent!("first_session", kind: "milestone")
    @user.project.update!(hackatime_projects: [], repo_later: false)

    nudge = deliver(at_slot(9))

    assert_equal [ "setup", "hackatime_project" ], [ nudge.kind, nudge.arm ]
    assert_match(/pick your project/, nudge.text)
    assert_equal "#{Rails.configuration.x.app_url}/project", nudge.destination_url
    assert_equal Hackatime.stubbed_projects["1001"].map(&:name), @user.project.reload.hackatime_baseline, "noted what you had, like opening your project page would"
    assert_equal "bandit", deliver(at_slot(10)).kind, "the project step waits a few days before saying it again"
  end

  test "a new hackatime project gets linked for you instead of asked about, and that DM is the day's message" do
    sent!("first_session", kind: "milestone")
    @user.project.update!(hackatime_projects: [], hackatime_baseline: [ "dotfiles" ],
                                  hackatime_baseline_seconds: { "dotfiles" => 11_160 })

    nudge = deliver(at_slot(9))

    assert_equal [ "rhythm-game" ], @user.project.reload.hackatime_projects
    assert_nil nudge
    assert_empty @sent
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_match(/linked to \*a rhythm game\* now/, dm[:args].second)
    assert_equal 0.0, @user.project.hours_logged, "its time is synced but held until it's confirmed (D-084)"
    @user.project.reload.update!(hackatime_auto_linked: false)
    assert_equal 1.5, Project.find(@user.project.id).hours_logged, "and counts at once when it is"
    assert_equal at_slot(9), @user.reload.slack_dmed_at
  end

  test "nothing within the hour of anything else the bot said" do
    @user.update!(slack_dmed_at: at_slot - 30.minutes)
    assert_nil deliver
    assert_empty @sent

    @user.update!(slack_dmed_at: at_slot - 2.hours)
    assert deliver.delivered
    assert_equal at_slot, @user.reload.slack_dmed_at
  end

  test "nothing on hackatime yet, and the bot says how to get time there: the plugin" do
    sent!("first_session", kind: "milestone")
    @user.project.update!(hackatime_projects: [], repo_later: false)
    before = Hackatime.stubbed_projects
    Hackatime.stubbed_projects = before.merge("1001" => [ Hackatime::Project.new("scratch", 0) ])

    nudge = deliver(at_slot(9))
    assert_equal [ "setup", "plugin" ], [ nudge.kind, nudge.arm ]
    assert_match(/turn the hackatime plugin on in your editor and write a line: a rhythm game links itself/, nudge.text)
    assert_equal "https://hackatime.hackclub.com/", nudge.destination_url
    assert_equal "bandit", deliver(at_slot(10)).kind, "said once, it waits a few days before saying it again"

    @user.nudges.delete_all
    @user.update!(slack_dmed_at: nil)
    Hackatime.stubbed_projects = before.merge("1001" => [])
    assert_equal "plugin", deliver(at_slot(9)).arm, "the hackatime project step itself is never asked for with nothing to pick"
  ensure
    Hackatime.stubbed_projects = before
  end

  test "a plugin nudge worked once hackatime has time from you" do
    nudge = sent!("plugin", kind: "setup", at: at_slot(8))
    @user.project.update!(hackatime_projects: [])
    before = Hackatime.stubbed_projects
    Hackatime.stubbed_projects = before.merge("1001" => [ Hackatime::Project.new("scratch", 0) ])
    travel_to(at_slot(11)) { Nudge.score_due }
    assert_equal 0, nudge.reload.reward

    Hackatime.stubbed_projects = before
    nudge.score!
    assert_equal 1, nudge.reload.reward
  ensure
    Hackatime.stubbed_projects = before
  end

  test "a pick-your-project nudge worked once a project's picked" do
    nudge = sent!("hackatime_project", kind: "setup", at: at_slot(8))
    travel_to(at_slot(11)) { Nudge.score_due }
    assert_equal 1, nudge.reload.reward

    @user.project.update!(hackatime_projects: [])
    nudge.score!
    assert_equal 0, nudge.reload.reward
  end

  test "the overtake copy knows who's just above you when they're within a session" do
    ana = users(:ana)
    ana.update!(hackatime_uid: "1002", hackatime_access_token: "token-heidi")
    ana.project.update!(hackatime_projects: [ "heidis-game" ])
    Hackatime.stubbed_spans["1002"] = [ span(at_slot(7, hour: 17), 120) ] # half an hour ahead of Orpheus
    at = at_slot(8)
    travel_to(at) do
      StreakActivity.sync_for_user!(ana)
      vars = Nudge::Context.new(@user.reload, at).tap(&:refresh!).vars
      assert_equal({ rank: 2, above: "pixelana", gap_minutes: 30 }, vars.slice(:rank, :above, :gap_minutes, :passed_by, :places_lost))
      assert Nudge::Copy.renderable?("overtake", vars)
      assert_includes Nudge::Bandit.new("behind").available_arms(Nudge::Context.new(@user, at)), "overtake"

      @user.project.update_columns(week_rank: 1, week_rank_on: at.to_date - 1) # Orpheus was first yesterday
      vars = Nudge::Context.new(@user.reload, at).vars
      assert_equal({ passed_by: "pixelana", places_lost: 1 }, vars.slice(:passed_by, :places_lost))

      Hackatime.stubbed_spans["1002"] = [ span(at_slot(7, hour: 17), 180) ] # too far ahead
      StreakActivity.sync_for_user!(ana.reload)
      vars = Nudge::Context.new(@user.reload, at).vars
      assert_equal({ rank: 2 }, vars.slice(:rank, :above, :gap_minutes, :passed_by))
      assert_not Nudge::Copy.renderable?("overtake", vars)
    end
  end

  test "names and titles that reach a nudge are escaped for Slack" do
    ana = users(:ana)
    ana.update!(hackatime_uid: "1002", hackatime_access_token: "token-heidi", slack_display_name: "<!channel> pixel & ana")
    ana.project.update!(hackatime_projects: [ "heidis-game" ])
    @user.project.update!(name: "<https://evil.example|Claim> game")
    Hackatime.stubbed_spans["1002"] = [ span(at_slot(7, hour: 17), 120) ]
    at = at_slot(8)
    travel_to(at) do
      StreakActivity.sync_for_user!(ana)
      vars = Nudge::Context.new(@user.reload, at).tap(&:refresh!).vars
      assert_equal "&lt;!channel&gt; pixel &amp; ana", vars[:above]
      assert_equal "&lt;https://evil.example|Claim&gt; game", vars[:title]

      @user.project.update_columns(week_rank: 1, week_rank_on: at.to_date - 1)
      assert_equal "&lt;!channel&gt; pixel &amp; ana", Nudge::Context.new(@user.reload, at).vars[:passed_by]

      @user.update!(first_name: "<!here>")
      assert_equal "&lt;!here&gt;", Nudge::Context.new(@user.reload, at).vars[:first_name]
    end
  end

  test "the bandit picks an arm that fits where you are, and logs the odds it picked it at" do
    sent!("first_session", kind: "milestone")
    comeback_sent!(10)
    nudge = deliver(at_slot(10))

    assert_equal "lapsed", nudge.bucket # 1.5 hours, but nothing in the last couple of days
    assert_includes Nudge::Bandit::ARMS["lapsed"], nudge.arm
    assert_operator nudge.propensity, :>, 0
    assert nudge.text.present?
  end

  test "nothing outside your slot, quiet hours, Save Point's dates, or once the bot's stopped" do
    assert_nil deliver(at_slot(8, hour: 18))
    assert_nil deliver(at_slot(8, hour: 19, min: 15))
    assert_nil deliver(at_slot(5))
    assert_nil deliver(at_slot(17))

    @user.update!(slack_muted_at: Time.current)
    assert_nil deliver
    assert_empty @sent
  end

  test "nothing if you've had one today, or already built today" do
    sent!("first_session", kind: "milestone", at: at_slot(8, hour: 9))
    assert_nil deliver

    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(8, hour: 17), 25) ] }
    @user.nudges.delete_all
    assert_nil deliver
  end

  def failing_dm(code)
    SlackBot.define_singleton_method(:dm) { |*, on_error: nil, **| on_error&.call(code) && nil }
  end

  def with_slack_configured
    configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, true
    yield
  ensure
    Rails.configuration.x.slack_configured = configured
  end

  test "a DM that doesn't go is kept with Slack's reason, and cleared when a later one does" do
    failing_dm("user_disabled")
    with_slack_configured do
      assert_not deliver.delivered
      @user.reload
      assert @user.slack_dm_failed_at
      assert_equal "user_disabled", @user.slack_dm_error
    end

    SlackBot.define_singleton_method(:dm) { |*, **| SlackMessage.new("D0ORPHEUS", "1.0") }
    with_slack_configured do
      assert deliver(at_slot(10)).delivered
      @user.reload
      assert_nil @user.slack_dm_failed_at
      assert_nil @user.slack_dm_error
    end
  end

  test "a long error code is cut to 100 characters" do
    failing_dm("x" * 150)
    with_slack_configured { deliver }
    assert_equal 100, @user.reload.slack_dm_error.length
  end

  test "a failed DM is skipped for a day, then tried again" do
    @user.update!(slack_dm_failed_at: at_slot - 1.hour, slack_dm_error: "user_disabled")
    assert_not Nudge::Context.new(@user, at_slot).reachable?
    assert_not_includes due_users(at_slot), @user

    @user.update!(slack_dm_failed_at: at_slot - Nudge::DM_RETRY_AFTER - 1.minute)
    assert Nudge::Context.new(@user, at_slot).reachable?
    assert_includes due_users(at_slot), @user
  end

  test "a DM that failed seconds after the slot opened is retried by the in-slot run a day later" do
    opens = at_slot(min: 0)
    @user.update!(slack_dm_failed_at: opens - 1.day + 5.seconds, slack_dm_error: "user_disabled")

    assert_includes due_users(opens + 3.seconds), @user
  end

  def due_users(now)
    reached = []
    original = Nudge.method(:deliver_to)
    Nudge.define_singleton_method(:deliver_to) { |user, _now = nil| reached << user }
    Nudge.deliver_due(now)
    reached
  ensure
    Nudge.define_singleton_method(:deliver_to, original)
  end

  test "a bandit or comeback nudge worked if you built at all in the two hours after it" do
    worked = sent!("tiny_step", at: at_slot(8))
    late = sent!("pledge", at: at_slot(9))
    comeback = sent!("comeback", kind: "comeback", at: at_slot(10))
    opted_out = sent!("tiny_step", at: at_slot(11))
    opted_out.update!(opted_out_at: at_slot(11) + 1.minute)
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(8) + 30.minutes, 2), span(at_slot(9) + 3.hours, 30), span(at_slot(10) + 110.minutes, 5), span(at_slot(11) + 5.minutes, 30) ] }

    travel_to(at_slot(13)) { Nudge.score_due }

    assert_equal [ 1, 0, 1, Nudge::OPT_OUT_PENALTY ], [ worked, late, comeback, opted_out ].map { |nudge| nudge.reload.reward }
  end

  test "a streak saver, milestone or program nudge still worked if you built 20 minutes in the six hours after it" do
    worked = sent!("streak_saver", kind: "streak_saver", at: at_slot(8))
    short = sent!("halfway", kind: "milestone", at: at_slot(9))
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(8) + 5.hours, 25), span(at_slot(9) + 1.hour, 19) ] }

    travel_to(at_slot(11)) { Nudge.score_due }

    assert_equal [ 1, 0 ], [ worked, short ].map { |nudge| nudge.reload.reward }
  end

  test "a nudge keeps the reward it was scored with" do
    old = sent!("tiny_step", at: at_slot(8))
    old.update!(reward: 0, rewarded_at: at_slot(8, hour: 23))
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(8) + 30.minutes, 30) ] }

    travel_to(at_slot(11)) { Nudge.score_due }

    assert_equal 0, old.reload.reward
  end

  test "a setup nudge worked if the step it asked for got done, whether or not they built" do
    linked = sent!("hackatime", kind: "setup", at: at_slot(8)) # Hackatime's linked in setup
    no_repo = sent!("repo", kind: "setup", at: at_slot(9))
    @user.project.update!(repo_later: false)
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(9, hour: 20), 30) ] } # built, but no repo added

    travel_to(at_slot(11)) { Nudge.score_due }

    assert_equal [ 1, 0 ], [ linked, no_repo ].map { |nudge| nudge.reload.reward }
  end

  test "setup nudges scored on building can be rescored on their step" do
    linked = sent!("hackatime", kind: "setup", at: at_slot(8))
    linked.update!(reward: 0, rewarded_at: at_slot(9))
    stopped = sent!("repo", kind: "setup", at: at_slot(8))
    stopped.update!(reward: Nudge::OPT_OUT_PENALTY, opted_out_at: at_slot(8, hour: 20), rewarded_at: at_slot(9))
    unscored = sent!("repo", kind: "setup", at: at_slot(10))

    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("nudges:rescore_setup")
    travel_to(at_slot(11)) { capture_io { Rake::Task["nudges:rescore_setup"].execute } }

    assert_equal [ 1, Nudge::OPT_OUT_PENALTY, nil ], [ linked, stopped, unscored ].map { |nudge| nudge.reload.reward }
  end

  test "the window has to close before a nudge is scored" do
    nudge = sent!("tiny_step", at: at_slot(8))
    saver = sent!("streak_saver", kind: "streak_saver", at: at_slot(8))
    travel_to(at_slot(8) + 1.hour) { Nudge.score_due }
    assert_nil nudge.reload.reward

    travel_to(at_slot(8) + 3.hours) { Nudge.score_due }
    assert_equal 0, nudge.reload.reward, "two hours is enough for a bandit nudge"
    assert_nil saver.reload.reward, "the rest still have six"
  end
end
