# Where the Slack bot token comes from: ENV["SLACK_BOT_TOKEN"] first, then Rails credentials (slack.bot_token).
module SlackBotToken
  def self.resolve(env: ENV, credentials: Rails.application.credentials)
    env["SLACK_BOT_TOKEN"].presence || (credentials.slack || {})[:bot_token].presence
  end
end
