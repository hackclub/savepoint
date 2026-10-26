namespace :nudges do
  # One of each kind of nudge, to someone on Slack, through the real thing (copy, tracked links), with made-up numbers. Marked as tests, so they're never scored or counted. Run it
  # where the links should go, like production:
  #
  #   bin/rails "nudges:test[U05F4B48GBF]"
  desc "DM someone one of each kind of nudge, for testing"
  task :test, [ :slack_id ] => :environment do |_, args|
    user = User.find_by!(slack_id: args.fetch(:slack_id))
    vars = { first_name: user.first_name, title: "flappy sheets", prize: "8BitDo Micro", a_prize: "an 8BitDo Micro", hours: "3.5", hours_word: "hours",
             hours_left: "6.5", hours_left_word: "hours", percent: 35, sessions_left: 9, sessions_word: "sessions", session_percent: 8, pace: 45, build_time: "evening",
             finish_on: "Oct 17", local_time: "7pm", days_left: 9, streak: 4, streak_word: "days", streak_next: 5,
             next_reward: "a shoutout in slack", days_to_reward: 1, reward_days_word: "day", peers: 6, days_idle: 3,
             minutes: 48, day: "today", next_day: "tomorrow", rank: 12, above: "pixelana", gap_minutes: 25, gap_word: "minutes", passed_by: "pixelana", places_lost: 2 }

    %w[progress tiny_step streak social overtake done cheer_done cheer_progress cheer_streak cheer_tomorrow cheer_social].each do |arm|
      nudge = user.nudges.new(kind: "test", arm:)
      nudge.deliver!(vars)
      puts "#{arm}: #{nudge.delivered ? "sent" : "not sent"}, #{nudge.link_url}"
    end
  end

  # One time: setup nudges scored before they were scored on their own step (the old rule was building 20 minutes,
  # which someone with Hackatime unlinked couldn't even do). Rescores each on whether the step's done now, which is
  # what scoring does anyway, since nothing records when a step was done. Opt-outs stay opt-outs.
  #
  #   bin/rails nudges:rescore_setup
  desc "Rescore already-scored setup nudges on whether the step they asked for got done"
  task rescore_setup: :environment do
    nudges = Nudge.delivered.real.scored.where(kind: "setup")
    before = nudges.group(:arm, :reward).count
    nudges.find_each(&:score!)
    after = nudges.reload.group(:arm, :reward).count
    puts "#{nudges.count} rescored. before: #{before.inspect}, after: #{after.inspect}"
  end
end
