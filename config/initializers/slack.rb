# The "Save Point" Slack app in the Hack Club workspace (app ID A0CBA5E9K7V). Its manifest is slack-manifest.json.
# Bot scopes: chat:write, channels:manage, groups:write, users:read, emoji:read. See SlackMessageJob.
#
# The bot token comes from ENV["SLACK_BOT_TOKEN"] first (.env locally, an Orchard env var in production),
# then from Rails credentials (bin/rails credentials:edit):
#
#   slack:
#     bot_token: xoxb-…
#
# The channels are in Program::SLACK_CHANNEL_IDS, and the bot needs to be in them.
#
# Without a bot token nothing's sent, only logged. Outside production the token is not used either, unless
# SLACK_LIVE=1: a local .env often holds the production token, and a dev run must not post to real channels or DM
# real people (SlackBotToken.live?).
require Rails.root.join("lib/slack_bot_token")

bot_token = SlackBotToken.configured

Slack.configure { |config| config.token = bot_token }
Rails.application.config.x.slack_configured = bot_token.present?

if bot_token.blank? && !Rails.env.test?
  if SlackBotToken.resolve.present?
    Rails.logger.warn("Slack sending is off outside production (set SLACK_LIVE=1 to allow): Slack messages are only logged")
  else
    Rails.logger.warn("Slack bot token missing (SLACK_BOT_TOKEN or credentials slack.bot_token): Slack messages are only logged")
  end
end

# Where links in Slack messages go.
Rails.application.config.x.app_url = ENV.fetch("APP_URL", "https://savepoint.hackclub.com")

# A GIF on each participant DM (SlackGifs). Off unless SLACK_GIFS=1, in every environment.
Rails.application.config.x.slack_gifs = ENV["SLACK_GIFS"] == "1"
