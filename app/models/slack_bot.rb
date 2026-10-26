# The bot, for messages we keep track of (like Nudge): a DM's Slack message ({ channel:, ts: }), or nil if it
# didn't go. A caller that wants to know why passes on_error, which gets Slack's error code (a string like
# "not_in_channel" or "user_disabled") when Slack refuses. Posting to someone's Slack ID DMs them, without the bot needing im:write. Fire-and-forget messages go
# through SlackMessageJob instead.
module SlackBot
  def self.dm(slack_id, text:, blocks:, on_error: nil)
    unless Rails.configuration.x.slack_configured
      Rails.logger.info("Slack (not configured) to #{slack_id}: #{text}")
      return
    end

    Slack::Web::Client.new.chat_postMessage(channel: slack_id, text:, blocks:, unfurl_links: false)
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
  rescue Slack::Web::Api::Errors::SlackError => error
    Rails.logger.warn("Slack DM to #{slack_id} failed: #{error.message}")
    on_error&.call(error.message)
    nil
  end

  # Runs the block (a Slack call into a public channel). If Slack says the bot isn't in the channel, it joins
  # (conversations.join, scope channels:join) and runs the block once more. A failed join raises its own Slack error.
  def self.joining(client, channel)
    yield
  rescue Slack::Web::Api::Errors::SlackError => error
    raise unless error.message == "not_in_channel"

    client.conversations_join(channel:)
    yield
  end
end
