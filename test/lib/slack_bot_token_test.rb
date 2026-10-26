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
end
