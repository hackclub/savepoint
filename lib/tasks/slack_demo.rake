require Rails.root.join("lib/slack_demo")

namespace :slack do
  # Every message the bot can send, to one person as DMs, from made-up data. Nothing is saved and nothing goes to a
  # channel or to anyone else.
  #
  #   bin/rails "slack:demo[U05F4B48GBF]"
  desc "DM one person (a Slack user ID) every message the Save Point bot can send, as a demo"
  task :demo, [ :to ] => :environment do |_, args|
    SlackDemo.check_target!(args[:to])
    abort "Slack isn't configured (no bot token)." unless Rails.configuration.x.slack_configured
    puts "sent #{SlackDemo.new(args[:to]).deliver!} messages (each after a label) to #{args[:to]}"
  rescue SlackDemo::Refused => error
    abort error.message
  end

  namespace :demo do
    # The same messages in tmp/slack_demo.md, nothing sent. Needs no token.
    desc "Write every demo message to tmp/slack_demo.md without sending"
    task preview: :environment do
      demo = SlackDemo.new("UDEMO0000")
      Rails.root.join(SlackDemo::PREVIEW_PATH).write(demo.preview)
      puts "#{demo.messages.size} messages written to #{SlackDemo::PREVIEW_PATH}"
    end
  end
end
