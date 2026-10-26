require "test_helper"

class JoinSlackChannelsSweepJobTest < ActiveJob::TestCase
  setup do
    @configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, true
    @invite = Slack::Web::Client.instance_method(:conversations_invite)
    @join = Slack::Web::Client.instance_method(:conversations_join)
    @invited = []
    User.update_all(slack_channels_joined_at: nil, slack_channels_failed_at: nil, slack_id: nil)
    @linked = users(:ana)
    @linked.update_columns(slack_id: "U0ANA")
  end

  teardown do
    Rails.configuration.x.slack_configured = @configured
    Slack::Web::Client.define_method(:conversations_invite, @invite)
    Slack::Web::Client.define_method(:conversations_join, @join)
  end

  # The bot can't join the channel itself (a private one), so "not_in_channel" stays a block.
  def stub_join_refused
    Slack::Web::Client.define_method(:conversations_join) do |**|
      raise Slack::Web::Api::Errors::SlackError.new("method_not_supported_for_channel_type")
    end
  end

  def stub_invite(errors = {})
    invited = @invited
    Slack::Web::Client.define_method(:conversations_invite) do |channel:, users:|
      invited << users
      raise Slack::Web::Api::Errors::SlackError.new(errors[users]) if errors[users]
      {}
    end
  end

  test "adds only people whose Slack is linked and who aren't in yet" do
    joined = users(:orpheus)
    joined.update_columns(slack_id: "U0JOINED", slack_channels_joined_at: 1.day.ago)
    User.create!(name: "Fay", email: "fay@example.com", hca_id: "ident!fay", slack_id: "U0FAILED", slack_channels_failed_at: 1.day.ago)
    User.create!(name: "Nina", email: "nina@example.com", hca_id: "ident!nina")
    stub_invite

    JoinSlackChannelsSweepJob.perform_now

    assert_equal [ "U0ANA" ], @invited
    assert_not_nil @linked.reload.slack_channels_joined_at
  end

  test "stops the run when the bot isn't in the channel, and tries again next run" do
    users(:orpheus).update_columns(slack_id: "U0ORPHEUS")
    stub_invite("U0ANA" => "not_in_channel", "U0ORPHEUS" => "not_in_channel")
    stub_join_refused

    JoinSlackChannelsSweepJob.perform_now
    assert_equal 1, @invited.size, "one call, not one per person"
    assert_nil @linked.reload.slack_channels_joined_at

    stub_invite
    @invited.clear
    JoinSlackChannelsSweepJob.perform_now
    assert_equal %w[U0ANA U0ORPHEUS].sort, @invited.sort
  end

  test "someone Slack refuses for good is skipped from then on" do
    stub_invite("U0ANA" => "user_is_restricted")
    JoinSlackChannelsSweepJob.perform_now
    assert_not_nil @linked.reload.slack_channels_failed_at

    @invited.clear
    JoinSlackChannelsSweepJob.perform_now
    assert_empty @invited
  end

  test "is on the recurring schedule" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    assert_equal "JoinSlackChannelsSweepJob", config.dig("production", "join_slack_channels", "class")
  end
end
