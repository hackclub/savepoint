require "test_helper"

# A token is present but sending is off (any environment but production, SLACK_LIVE unset): nothing reaches Slack.
class SlackSendingOffTest < ActiveJob::TestCase
  Credentials = Struct.new(:slack)

  setup do
    @configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, false
    @methods = %i[chat_postMessage chat_postEphemeral conversations_join conversations_invite users_info].index_with { |name| Slack::Web::Client.instance_method(name) }
    @calls = []
    calls = @calls
    @methods.each_key { |name| Slack::Web::Client.define_method(name) { |**args| calls << [ name, args ]; {} } }
  end

  teardown do
    Rails.configuration.x.slack_configured = @configured
    @methods.each { |name, original| Slack::Web::Client.define_method(name, original) }
  end

  test "the initializer's token is nil with a token present and SLACK_LIVE unset" do
    token = SlackBotToken.configured(env: { "SLACK_BOT_TOKEN" => "xoxb-present" }, credentials: Credentials.new(nil), rails_env: ActiveSupport::StringInquirer.new("development"))
    assert_nil token
  end

  test "SlackMessageJob does not call the Slack client" do
    SlackMessageJob.perform_now("C0CBHCHK469", "hi")
    assert_empty @calls
  end

  test "the reward shoutout does not call the Slack client" do
    perform_enqueued_jobs do
      RewardNotifier.earned(Struct.new(:key, :announce_at, :users).new("streak_shoutout", nil, [ users(:orpheus) ]))
    end
    assert_empty @calls
  end

  test "SlackBot.dm, the profile and join jobs do not call the Slack client" do
    assert_nil SlackBot.dm("U123", text: "hi", blocks: [])
    assert_empty @calls
  end

  test "the announcement and the demo refuse to send" do
    assert_raises(SlackAnnouncement::Refused) { SlackAnnouncement.live!(live: false) }
    assert_raises(SlackDemo::Refused) { SlackDemo.new("U123").deliver! } unless SlackBotToken.live?
    assert_empty @calls
  end
end
