# Posts one message from the bot: to someone's Slack ID, which DMs them, or to a channel's ID. `text` is what
# shows in notifications; the message itself is app/views/slack/message.slack_message.slocks, with a button if
# there's a `link` ([ label, url ]) and a GIF after the text if there's a `gif` key (SlackGifs) and they're switched on. A DM is noted as the bot's latest to them (User#slack_dmed!), which spaces its
# messages out. (Like Stardance's SendSlackDmJob.)
class SlackMessageJob < ApplicationJob
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: 30.seconds, attempts: 3

  # The blocks for a message: its text, its GIF if it has a `gif` key (SlackGifs) and they're on, then the button.
  # `gifs: true` draws the GIF whatever the switch says (SlackDemo).
  def self.blocks(text, link, gif: nil, gifs: false)
    rendered = ApplicationController.renderer.new.render(template: "slack/message", formats: [ :slack_message ], locals: { text:, link: })
    blocks = JSON.parse(rendered).fetch("blocks")
    image = SlackGifs.block(gif, force: gifs)
    blocks.insert(1, image.deep_stringify_keys) if image
    blocks
  end

  def perform(channel, text, link: nil, gif: nil)
    return Rails.logger.info("Slack (not configured) to #{channel}: #{text}") unless Rails.configuration.x.slack_configured

    client = Slack::Web::Client.new
    post = -> { client.chat_postMessage(channel:, text:, unfurl_links: false, blocks: self.class.blocks(text, link, gif:)) }
    # A channel (C…) may not have the bot in it yet: it joins and tries again. A DM never needs that.
    channel.start_with?("C") ? SlackBot.joining(client, channel, &post) : post.call
    User.find_by(slack_id: channel)&.slack_dmed!
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
  rescue Slack::Web::Api::Errors::SlackError => error
    # They left the workspace, or can't be DMed: nothing to do but note it.
    Rails.logger.warn("Slack message to #{channel} failed: #{error.message}")
  end
end
