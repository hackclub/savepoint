require "test_helper"

class RewardTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @orpheus, @ana = users(:orpheus), users(:ana)
    @spans_before = Hackatime.stubbed_spans
  end

  teardown { Hackatime.stubbed_spans = @spans_before }

  # Days someone built `minutes` on, as numbers from 6 (Oct 27): 9 is Oct 30, and 15 is Nov 5.
  def built(user, days, minutes: 20)
    days.each { |day| user.streak_activities.create!(activity_date: Date.new(2026, 10, 21) + day, coded_seconds: minutes * 60) }
  end

  def stub_const_channel(id)
    Program.send(:remove_const, :SHOUTOUT_CHANNEL_ID)
    Program.const_set(:SHOUTOUT_CHANNEL_ID, id)
    yield
  ensure
    Program.send(:remove_const, :SHOUTOUT_CHANNEL_ID)
    Program.const_set(:SHOUTOUT_CHANNEL_ID, "C0CBHCHK469")
  end

  def slack_messages
    enqueued_jobs.select { |job| job[:job] == SlackMessageJob }.map { |job| job[:args].first(2) }
  end

  test "a streak earns two perks, a gold star at 3 days and a shoutout at 5, each once, and each sends a DM" do
    assert_equal [ [ "gold_star", 3 ], [ "streak_shoutout", 5 ] ], Reward::STREAK.map { [ _1[:key], _1[:days] ] }
    assert_empty Reward::HOURS

    built(@orpheus, 6..8)
    travel_to(Time.utc(2026, 10, 29, 12)) { @orpheus.recalculate_streak! }
    assert_equal %w[gold_star], @orpheus.rewards.pluck(:key)
    assert_includes slack_messages, [ "U0ORPHEUS", "3-day streak!! You now have a gold star on your sheet :cat-lock-in:" ]

    built(@orpheus, 9..10)
    travel_to(Time.utc(2026, 10, 31, 12)) { @orpheus.recalculate_streak! }
    assert_equal %w[gold_star streak_shoutout], @orpheus.rewards.pluck(:key).sort
    assert_includes slack_messages, [ "U0ORPHEUS", "5-day streak!! You've earned a shoutout in Slack for *#{@orpheus.project.title}* :yayayayayay:" ]

    travel_to(Time.utc(2026, 10, 31, 13)) { @orpheus.recalculate_streak! }
    assert_equal 2, @orpheus.rewards.count
  end

  test "the shoutout posts to #savepoint" do
    assert_equal "C0CBHCHK469", Program::SHOUTOUT_CHANNEL_ID
    built(@orpheus, 6..10)
    travel_to(Time.utc(2026, 10, 31, 12)) { @orpheus.recalculate_streak! }

    assert @orpheus.earned?("streak_shoutout")
    assert_includes slack_messages, [ "C0CBHCHK469", "🔥 <@U0ORPHEUS> has a 5-day streak, building *#{@orpheus.project.title}*." ]
  end

  test "a title with Slack markup can't ping the channel or post a link" do
    @orpheus.project.update!(name: "<!channel> <https://evil.example|x> & co")
    built(@orpheus, 6..10)
    travel_to(Time.utc(2026, 10, 31, 12)) { @orpheus.recalculate_streak! }

    post = slack_messages.find { |channel, _text| channel == "C0CBHCHK469" }.last
    assert_includes post, "*&lt;!channel&gt; &lt;https://evil.example|x&gt; &amp; co*"
    assert_not_includes post, "<!channel>"
    assert_not_includes post, "<https"
    assert_includes post, "<@U0ORPHEUS>", "the mention the code builds is left alone"
    dm = slack_messages.find { |channel, text| channel == "U0ORPHEUS" && text.include?("5-day") }.last
    assert_not_includes dm, "<!channel>"
  end

  test "someone not on Slack is named by their escaped public name" do
    @orpheus.update!(slack_id: nil, slack_display_name: "<!channel> orph")
    built(@orpheus, 6..10)
    travel_to(Time.utc(2026, 10, 31, 12)) { @orpheus.recalculate_streak! }

    post = slack_messages.find { |channel, _text| channel == "C0CBHCHK469" }.last
    assert_includes post, "&lt;!channel&gt; orph has a 5-day streak"
  end

  test "with no channel set, the shoutout only logs" do
    built(@orpheus, 6..10)
    logged = StringIO.new
    old_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)
    stub_const_channel(nil) { travel_to(Time.utc(2026, 10, 31, 12)) { @orpheus.recalculate_streak! } }
    Rails.logger = old_logger

    assert_equal [ "U0ORPHEUS" ], slack_messages.map(&:first).uniq, "only DMs, nothing to any channel"
    assert_match(/Slack \(no Save Point channel\): would post .*5-day streak/, logged.string)
  end

  test "logged hours earn no reward" do
    @orpheus.project.update!(hackatime_projects: [ "rhythm-game" ])
    link_hackatime(@orpheus)
    built(@orpheus, 6..8, minutes: 120)
    travel_to(Time.utc(2026, 10, 29, 12)) { @orpheus.recalculate_streak! }
    assert_not @orpheus.earned?("hours_shoutout")
    assert_equal %w[gold_star], @orpheus.rewards.pluck(:key)
  end

  test "shoutouts each get their own slot, 10 minutes after the last" do
    [ @orpheus, @ana ].each { |user| built(user, 6..10) }
    now = Time.utc(2026, 10, 31, 12)
    travel_to(now) { [ @orpheus, @ana ].each(&:recalculate_streak!) }

    assert_equal [ now, now + 10.minutes ], [ @orpheus, @ana ].map { |user| user.rewards.find_by(key: "streak_shoutout").announce_at }
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" && job[:args].second.start_with?("5-day") }
    assert_equal (now + 10.minutes).to_f, dm[:at]
    assert_nil @orpheus.rewards.find_by(key: "gold_star").announce_at
  end

  test "rewards from before D-018 stay readable" do
    old = Reward.new(user: @orpheus, key: "flame")
    assert_not old.valid?, "nothing new is earned with a retired key"
    Reward.insert_all!([ { user_id: @orpheus.id, key: "skip_day", created_at: Time.current, updated_at: Time.current } ])
    reward = @orpheus.rewards.find_by(key: "skip_day")
    assert_nil reward.definition
    assert_equal [ @orpheus ], reward.users
    assert @orpheus.earned?("skip_day")
    assert reward.update(announce_at: nil), "an old row still saves"
  end

  test "there is no skip day: a missed day ends the streak" do
    built(@orpheus, [ *6..12, 14, 15 ])
    travel_to(Time.utc(2026, 11, 5, 12)) do
      @orpheus.recalculate_streak!
      assert_equal 2, @orpheus.current_streak
      assert_nil @orpheus.streak_skip_used_on
    end
  end

  test "Slack messages render as blocks with a button" do
    rendered = ApplicationController.renderer.new.render(template: "slack/message", formats: [ :slack_message ],
                                                          locals: { text: "hi", link: [ "Open Save Point", "https://savepoint.hackclub.com/project" ] })
    blocks = JSON.parse(rendered)["blocks"]
    assert_equal "hi", blocks[0]["text"]["text"]
    assert_equal "https://savepoint.hackclub.com/project", blocks[1]["elements"][0]["url"]
  end

  # The stickers (D-051): five minutes on the linked project inside the hour after signing up.
  def sticker_user(created_at: Time.utc(2026, 10, 25, 10), project_names: [ "rhythm-game" ])
    link_hackatime(@orpheus)
    @orpheus.project.update!(hackatime_projects: project_names)
    @orpheus.update_column(:created_at, created_at)
    @orpheus
  end

  def log_span(user, start, minutes)
    Hackatime.stubbed_spans = { user.hackatime_uid => [ hackatime_span(start, minutes) ] }
  end

  def award_stickers_at(user, time)
    travel_to(time) { Reward.award_stickers!(user.reload) }
  end

  test "five minutes on the linked project in the first hour earns the stickers, and the DM links to the shop" do
    user = sticker_user
    log_span(user, user.created_at + 10.minutes, 5)
    award_stickers_at(user, user.created_at + 30.minutes)

    assert user.reload.earned?("stickers")
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob }
    assert_equal [ "U0ORPHEUS", "Stickers!! You worked on your game in your first hour, so free Hack Club stickers are yours :yayayayayay: Tell us where to send them." ], dm[:args].first(2)
    assert_equal [ "Claim your stickers", "https://savepoint.hackclub.com/shop" ], dm[:args].third["link"]
    assert_equal [ "U0ORPHEUS" ], slack_messages.map(&:first), "a DM only, no post in the channel"
  end

  test "the first-hour stickers are not earned past 3 packs" do
    user = sticker_user
    Reward::COMEBACK_STICKER_KEYS.each { |key| user.rewards.create!(key:) }
    log_span(user, user.created_at + 10.minutes, 5)
    award_stickers_at(user, user.created_at + 30.minutes)

    assert_not user.reload.earned?("stickers")
    assert_equal 3, Reward.sticker_packs_earned(user)
  end

  test "four minutes is not enough" do
    user = sticker_user
    log_span(user, user.created_at + 10.minutes, 4)
    award_stickers_at(user, user.created_at + 30.minutes)

    assert_not user.reload.earned?("stickers")
  end

  test "time before signing up is clipped out of the window" do
    user = sticker_user
    log_span(user, user.created_at - 3.minutes, 7) # 3 before, 4 after
    award_stickers_at(user, user.created_at + 30.minutes)
    assert_not user.reload.earned?("stickers")

    log_span(user, user.created_at - 3.minutes, 8) # 3 before, 5 after
    award_stickers_at(user, user.created_at + 30.minutes)
    assert user.reload.earned?("stickers")
  end

  test "time after the first hour is clipped out too" do
    user = sticker_user
    log_span(user, user.created_at + 57.minutes, 8) # 3 in the hour
    award_stickers_at(user, user.created_at + 90.minutes)

    assert_not user.reload.earned?("stickers")
  end

  test "an account made before the stickers began never earns them" do
    user = sticker_user(created_at: Reward::STICKERS_SINCE - 1.minute)
    log_span(user, user.created_at + 10.minutes, 20)
    award_stickers_at(user, user.created_at + 30.minutes)

    assert_not user.reload.earned?("stickers")
    assert_equal Time.utc(2026, 10, 25), Reward::STICKERS_SINCE
  end

  test "with no project linked there is nothing to count" do
    user = sticker_user(project_names: [])
    log_span(user, user.created_at + 10.minutes, 20)
    award_stickers_at(user, user.created_at + 30.minutes)

    assert_not user.reload.earned?("stickers")
  end

  test "they are earned once" do
    user = sticker_user
    log_span(user, user.created_at + 10.minutes, 6)
    award_stickers_at(user, user.created_at + 30.minutes)
    award_stickers_at(user, user.created_at + 40.minutes)
    assert_equal 1, user.rewards.where(key: "stickers").count
  end

  test "nobody is asked about three hours after signing up" do
    user = sticker_user
    watched = Class.new(Hash) { attr_reader :asked; def fetch(*) = (@asked = true; super) }.new
    Hackatime.stubbed_spans = watched
    award_stickers_at(user, user.created_at + 3.hours)
    assert_not watched.asked, "no request three hours after signing up"
  end

  test "a sync earns them: the streak recalculation checks the stickers" do
    user = sticker_user
    log_span(user, user.created_at + 10.minutes, 5)
    travel_to(user.created_at + 30.minutes) { user.reload.recalculate_streak! }

    assert user.reload.earned?("stickers")
  end

  # The stickers are for people Hack Club Auth calls YSWS-eligible and Hackatime hasn't banned (D-051).
  def with_trust_levels(levels)
    before = Hackatime.stubbed_trust_levels
    Hackatime.stubbed_trust_levels = levels
    yield
  ensure
    Hackatime.stubbed_trust_levels = before
  end

  def sticker_user_with_minutes(minutes = 5)
    user = sticker_user
    log_span(user, user.created_at + 10.minutes, minutes)
    user
  end

  test "an eligible account earns the stickers and has its trust level stored" do
    user = sticker_user_with_minutes
    with_trust_levels(user.hackatime_uid => "green") { award_stickers_at(user, user.created_at + 30.minutes) }

    assert user.reload.earned?("stickers")
    assert_equal "green", user.hackatime_trust_level
  end

  test "an account Hack Club Auth calls ineligible does not earn them, even with five minutes" do
    user = sticker_user_with_minutes
    user.update!(ysws_eligible: false)
    with_trust_levels(user.hackatime_uid => "blue") { award_stickers_at(user, user.created_at + 30.minutes) }

    assert_not user.reload.earned?("stickers")
  end

  test "a Hackatime-banned (red) account does not earn them" do
    user = sticker_user_with_minutes
    with_trust_levels(user.hackatime_uid => "red") { award_stickers_at(user, user.created_at + 30.minutes) }

    assert_not user.reload.earned?("stickers")
    assert_equal "red", user.hackatime_trust_level
  end

  test "when the trust lookup fails nothing is awarded, and a later sync can award" do
    user = sticker_user_with_minutes
    with_trust_levels(user.hackatime_uid => :unavailable) { award_stickers_at(user, user.created_at + 30.minutes) }
    assert_not user.reload.earned?("stickers")

    with_trust_levels(user.hackatime_uid => "blue") { award_stickers_at(user, user.created_at + 40.minutes) }
    assert user.reload.earned?("stickers")
  end

  test "the trust lookup is only made once they have the minutes" do
    user = sticker_user_with_minutes(4)
    with_trust_levels(user.hackatime_uid => :unavailable) { award_stickers_at(user, user.created_at + 30.minutes) }

    assert_nil user.reload.hackatime_trust_level
  end
end
