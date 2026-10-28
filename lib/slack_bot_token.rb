# Where the Slack bot token comes from: ENV["SLACK_BOT_TOKEN"] first, then Rails credentials (slack.bot_token).
#
# Sending is live only in production, or where SLACK_LIVE=1. Elsewhere `configured` returns nil, so the token is never
# handed to the Slack client and every sender only logs. A developer's .env often holds the production token.
module SlackBotToken
  def self.resolve(env: ENV, credentials: Rails.application.credentials)
    env["SLACK_BOT_TOKEN"].presence || (credentials.slack || {})[:bot_token].presence
  end

  def self.live?(env: ENV, rails_env: Rails.env)
    rails_env.production? || env["SLACK_LIVE"] == "1"
  end

  # The token to configure the Slack client with, or nil when sending is off.
  def self.configured(env: ENV, credentials: Rails.application.credentials, rails_env: Rails.env)
    resolve(env:, credentials:) if live?(env:, rails_env:)
  end
end
