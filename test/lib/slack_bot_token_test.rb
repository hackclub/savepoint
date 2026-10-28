require "test_helper"

class SlackBotTokenTest < ActiveSupport::TestCase
  Credentials = Struct.new(:slack)

  test "prefers ENV over credentials" do
    assert_equal "xoxb-env", SlackBotToken.resolve(env: { "SLACK_BOT_TOKEN" => "xoxb-env" }, credentials: Credentials.new({ bot_token: "xoxb-cred" }))
  end

  test "falls back to credentials when ENV is empty or unset" do
    credentials = Credentials.new({ bot_token: "xoxb-cred" })
    assert_equal "xoxb-cred", SlackBotToken.resolve(env: { "SLACK_BOT_TOKEN" => "" }, credentials:)
    assert_equal "xoxb-cred", SlackBotToken.resolve(env: {}, credentials:)
  end

  test "is nil when neither is set" do
    assert_nil SlackBotToken.resolve(env: {}, credentials: Credentials.new(nil))
  end

  test "is live in production, or with SLACK_LIVE=1" do
    assert SlackBotToken.live?(env: {}, rails_env: ActiveSupport::StringInquirer.new("production"))
    assert SlackBotToken.live?(env: { "SLACK_LIVE" => "1" }, rails_env: ActiveSupport::StringInquirer.new("development"))
    assert_not SlackBotToken.live?(env: {}, rails_env: ActiveSupport::StringInquirer.new("development"))
    assert_not SlackBotToken.live?(env: { "SLACK_LIVE" => "true" }, rails_env: ActiveSupport::StringInquirer.new("development"))
  end

  test "hands out no token outside production unless SLACK_LIVE=1" do
    env = { "SLACK_BOT_TOKEN" => "xoxb-env" }
    dev = ActiveSupport::StringInquirer.new("development")
    credentials = Credentials.new(nil)
    assert_nil SlackBotToken.configured(env:, credentials:, rails_env: dev)
    assert_equal "xoxb-env", SlackBotToken.configured(env: env.merge("SLACK_LIVE" => "1"), credentials:, rails_env: dev)
    assert_equal "xoxb-env", SlackBotToken.configured(env:, credentials:, rails_env: ActiveSupport::StringInquirer.new("production"))
  end

  test "the credentials token is gated too" do
    assert_nil SlackBotToken.configured(env: {}, credentials: Credentials.new({ bot_token: "xoxb-cred" }), rails_env: ActiveSupport::StringInquirer.new("development"))
  end
end
