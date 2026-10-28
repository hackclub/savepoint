# Every message the Save Point Slack app can send, with its GIF (SlackGifs) whatever SLACK_GIFS says, built through the real code (the notifiers, Nudge::Copy,
# Nudge::Message, SlackMessageJob's template) from made-up data, so someone can read them all. Sent as DMs to one
# person, never a channel (bin/rails "slack:demo[U...]"), or written to a file (bin/rails slack:demo:preview).
# Nothing is saved: the records here are plain objects, and jobs are caught before they run.
class SlackDemo
  class Refused < StandardError; end

  Message = Struct.new(:label, :text, :blocks)

  USER_ID = /\AU[A-Z0-9]{2,}\z/
  PREVIEW_PATH = "tmp/slack_demo.md"
  TITLE = "space game"

  Person = Struct.new(:slack_id, :slack_muted_at, :name, :public_name, :first_name, :project) do
    def slack_dmed! = nil
  end
  Pro = Struct.new(:title, :user, :deadline) do
    def reload = self
  end
  Ord = Struct.new(:project, :hours, :configuration)
  Ext = Struct.new(:project, :reason, :status)
  Rew = Struct.new(:key, :announce_at, :users)

  def self.check_target!(to)
    raise Refused, "give a Slack user ID: bin/rails \"slack:demo[U0123ABCD]\"" if to.blank?
    raise Refused, "#{to.inspect} is not a user ID (U...). Channels and everything else are refused." unless to.to_s.match?(USER_ID)
    to
  end

  attr_reader :to

  def initialize(to, client: nil, pause: 1)
    @to = to.to_s
    @client = client
    @pause = pause
  end

  def messages
    @messages ||= begin
      pieces = notifier_messages + nudge_messages
      pieces.each_with_index.map do |piece, index|
        piece.label = "— demo #{index + 1}/#{pieces.size}: #{piece.label} —"
        piece
      end
    end
  end

  # Posts the first label straight to the user ID, as SlackBot.dm does (conversations.open needs im:write, which the
  # bot lacks). Slack answers with the DM's channel. If that is not a DM (D...), it stops. Everything else goes to that
  # channel, one post a second, so only a DM is ever posted to.
  def deliver!
    self.class.check_target!(to)
    raise Refused, "Slack sending is off outside production (set SLACK_LIVE=1)" unless @client || SlackBotToken.live?
    client = @client || Slack::Web::Client.new
    channel = nil

    messages.each do |message|
      if channel.nil?
        channel = client.chat_postMessage(channel: to, text: message.label, unfurl_links: false).channel
        raise Refused, "Slack posted to #{channel.inspect}, not a DM" unless channel.to_s.start_with?("D")
      else
        client.chat_postMessage(channel:, text: message.label, unfurl_links: false)
      end
      sleep @pause
      client.chat_postMessage(channel:, text: message.text, blocks: message.blocks, unfurl_links: false)
      sleep @pause
    end
    messages.size
  end

  def preview
    messages.map do |message|
      "## #{message.label}\n\n#{message.text}\n\n```json\n#{JSON.pretty_generate(message.blocks)}\n```\n"
    end.join("\n").prepend("# Slack demo: #{messages.size} messages\n\nText is what shows in notifications. Blocks are what Slack draws.\n\n")
  end

  private
    def prize = Prize.find("micro")
    def app_url = Rails.configuration.x.app_url

    def person = @person ||= Person.new(to, nil, "Alex Example", "alex", "Alex", nil)

    def project = @project ||= Pro.new(TITLE, person, Date.current + 9).tap { |made| person.project = made }

    # What each notifier queues, caught instead of run, then drawn with SlackMessageJob's own template.
    def notifier_messages
      queued = capture_jobs do
        OrderNotifier.claimed(Ord.new(project, 6.5, prize.name))
        OrderNotifier.ordered(Ord.new(project, 6.5, prize.name))
        ExtensionNotifier.requested(Ext.new(project, "Stuck on the level editor, need a few more days.", "approved"))
        %w[approved denied].each { |status| ExtensionNotifier.decided(Ext.new(project, "x", status)) }
        RewardNotifier.earned(Rew.new("gold_star", nil, [ person ]))
        RewardNotifier.earned(Rew.new("streak_shoutout", nil, [ person ]))
        auto_link
      end
      labels = [ "order · admin DM", "order · ordered DM", "extension · admin DM", "extension · approved DM", "extension · denied DM",
                 "reward · gold star DM", "reward · streak shoutout DM", "project · auto-link DM" ]
      messages = queued.zip(labels).map { |(text, link, gif), label| rendered(label, text, link, gif) }
      messages << rendered("reward · streak shoutout channel post (shown here as a DM, never posted to a channel)", shoutout_post, nil)
    end

    def shoutout_post
      format(RewardNotifier::POSTS.fetch("streak_shoutout"), RewardNotifier.send(:vars_for, project))
    end

    def auto_link
      real = Project.new(name: TITLE)
      real.user = User.new(slack_id: to)
      real.user.define_singleton_method(:slack_dmed!) { nil }
      real.send(:dm_about_auto_link, "space-game-v2")
    end

    # [ [ text, link, gif ], ... ] for each SlackMessageJob queued in the block, in order.
    def capture_jobs
      adapter = ActiveJob::QueueAdapters::TestAdapter.new
      original_adapter = SlackMessageJob.queue_adapter
      original_admins = Rails.configuration.x.admin_slack_ids
      SlackMessageJob.queue_adapter = adapter
      Rails.configuration.x.admin_slack_ids = [ to ]
      yield
      # The shoutout's channel post is left out: the demo draws it itself, as a DM.
      adapter.enqueued_jobs.filter_map do |job|
        channel, text, options = ActiveJob::Arguments.deserialize(job.fetch("args", job[:args]))
        [ text, options && options[:link], options && options[:gif] ] unless channel.start_with?("C")
      end
    ensure
      SlackMessageJob.queue_adapter = original_adapter
      Rails.configuration.x.admin_slack_ids = original_admins
    end

    def rendered(label, text, link, gif = nil)
      Message.new(label, text, SlackMessageJob.blocks(text, link, gif:, gifs: true))
    end

    # Every variant of every arm, cheers and fixed nudges included, drawn with Nudge::Message.
    def nudge_messages
      vars = nudge_vars
      counted = 0 # each nudge gets the next GIF of its pool, so an arm shows a different GIF for each variant
      Nudge::Copy::ARMS.merge(Nudge::Copy::FIXED).flat_map do |arm, variants|
        kind = Nudge::Copy::ARMS.key?(arm) ? (arm.start_with?("cheer") ? "cheer" : "bandit") : "fixed"
        variants.each_with_index.map do |variant, index|
          missing = Nudge::Copy.keys(variant) - vars.keys
          raise "demo data is missing #{missing.join(", ")} for #{arm} variant #{index + 1}" if missing.any?

          nudge = Nudge.new(user: User.new(slack_id: to), kind: "test", arm:, text: format(variant, **vars), token: "demo")
          Message.new("nudge · #{arm} · #{kind} · variant #{index + 1}", nudge.text, Nudge::Message.new(nudge, gifs: true, pick: (counted += 1) - 1).blocks)
        end
      end
    end

    # Formatted the way Nudge::Context#vars does (hours without ".0", singular units, a prize with its article).
    def nudge_vars
      needed = prize.hours
      hours = 3.5
      left = needed - hours
      pace = 45
      sessions = (left * 60 / pace).ceil
      shown = ApplicationController.helpers.method(:project_hours)
      { first_name: "Alex", title: TITLE, prize: prize.name, a_prize: prize.with_article, hours: shown.call(hours), hours_word: "hours",
        hours_needed: shown.call(needed), hours_left: shown.call(left.round(1)), hours_left_word: left.round(1) == 1 ? "hour" : "hours",
        percent: (hours * 100 / needed).round, sessions_left: sessions, sessions_word: sessions == 1 ? "session" : "sessions",
        session_percent: (pace * 100.0 / (needed * 60)).round,
        pace:, build_time: "evening", finish_on: (Date.current + 9).strftime("%b %-d"), local_time: "7pm", days_left: 9, streak: 4, streak_word: "days",
        streak_next: 5, next_reward: "a shoutout in slack", days_to_reward: 1, reward_days_word: "day", peers: 6, days_idle: 3, minutes: 48,
        day: "today", next_day: "tomorrow", rank: 12, above: "pixelana", gap_minutes: 25, gap_word: "minutes", passed_by: "pixelana",
        places_lost: 2, sticker_minutes: 5, unshipped: "5.4", since: "since your last ship",
        added: "6.5", added_word: "hours", approved: "6.5", approved_word: "hours",
        goal: prize.with_article, goal_hours: shown.call(needed), still: shown.call((needed - 6.5).round(1)), still_word: "hours" }
    end
end
