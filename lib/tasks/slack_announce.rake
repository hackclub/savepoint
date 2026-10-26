require Rails.root.join("lib/slack_announcement")

namespace :slack do
  # Posts a Block Kit message file to a channel as Armand (his user token). Without CONFIRM=<channel id> it only
  # prints what it would do. Nothing posts to the wrong tool's channels.
  #
  #   bin/rails "slack:announce[C0123ABCD,announcements/example.json]"
  #   CONFIRM=C0123ABCD bin/rails "slack:announce[C0123ABCD,announcements/example.json]"
  desc "Post a Block Kit message file to a channel as Armand (needs SLACK_USER_TOKEN and CONFIRM=<channel id>)"
  task :announce, [ :channel, :file ] => :environment do |_, args|
    channel = SlackAnnouncement.check_channel!(args[:channel])
    message = SlackAnnouncement.load(args[:file])
    SlackAnnouncement.token!
    unless ENV["CONFIRM"] == channel
      puts "would post to #{channel}: #{message.blocks.size} blocks, text #{message.text.inspect}"
      puts "preview: #{message.preview_url}"
      abort "nothing posted. Run again with CONFIRM=#{channel} to post."
    end
    puts "posted to #{channel}: #{message.deliver!(channel)}"
  rescue SlackAnnouncement::Refused => error
    abort error.message
  rescue Slack::Web::Api::Errors::SlackError => error
    abort "Slack refused: #{error.message}"
  end

  namespace :announce do
    # Posts the message to the token owner's own DM, to see the real render. Posts nowhere else.
    desc "DM the token owner a Block Kit message file, to check how it renders"
    task :test, [ :file ] => :environment do |_, args|
      message = SlackAnnouncement.load(args[:file])
      puts "sent to your own DM: #{message.test!}"
    rescue SlackAnnouncement::Refused => error
      abort error.message
    rescue Slack::Web::Api::Errors::SlackError => error
      abort "Slack refused: #{error.message}"
    end

    # Checks the file and prints a Block Kit Builder link. Needs no token.
    desc "Check a Block Kit message file and print a Block Kit Builder link, nothing sent"
    task :preview, [ :file ] => :environment do |_, args|
      message = SlackAnnouncement.load(args[:file])
      puts "ok: #{message.blocks.size} blocks"
      puts "fallback text: #{message.text}"
      puts "Block Kit Builder: #{message.preview_url}"
    rescue SlackAnnouncement::Refused => error
      abort error.message
    end
  end
end
