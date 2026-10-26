require "test_helper"

class JoinSlackChannelsJobTest < ActiveJob::TestCase
  setup do
    @configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, true
    @invite = Slack::Web::Client.instance_method(:conversations_invite)
    @join = Slack::Web::Client.instance_method(:conversations_join)
    @joins = []
    @invites = []
    User.update_all(slack_channels_joined_at: nil, slack_channels_failed_at: nil)
  end

  teardown do
    Rails.configuration.x.slack_configured = @configured
    Slack::Web::Client.define_method(:conversations_invite, @invite)
    Slack::Web::Client.define_method(:conversations_join, @join)
  end

  # The bot's own join of a channel raises this Slack error (or succeeds when nil), and is recorded.
  def stub_join(error = nil)
    joins = @joins
    Slack::Web::Client.define_method(:conversations_join) do |**args|
      joins << args
      raise Slack::Web::Api::Errors::SlackError.new(error) if error
      {}
    end
  end

  # Every invite raises this Slack error (or succeeds when nil), and is recorded.
  def stub_invite(error = nil)
    invites = @invites
    Slack::Web::Client.define_method(:conversations_invite) do |**args|
      invites << args
      raise Slack::Web::Api::Errors::SlackError.new(error) if error
      {}
    end
  end

  test "Save Point's channel is the one people are added to" do
    assert_equal [ "C0CBHCHK469" ], Program::SLACK_CHANNEL_IDS
  end

  test "adds someone whose Slack is linked, and marks them joined" do
    stub_invite
    assert_equal :joined, JoinSlackChannelsJob.perform_now(users(:ana).id)

    assert_equal [ { channel: "C0CBHCHK469", users: "U0ANA" } ], @invites
    assert_not_nil users(:ana).reload.slack_channels_joined_at
  end

  test "already in the channel counts as joined" do
    stub_invite("already_in_channel")
    assert_equal :joined, JoinSlackChannelsJob.perform_now(users(:ana).id)
    assert_not_nil users(:ana).reload.slack_channels_joined_at
  end

  test "when the bot isn't in the channel, it joins it and invites again" do
    attempts = 0
    invites = @invites
    Slack::Web::Client.define_method(:conversations_invite) do |**args|
      invites << args
      raise Slack::Web::Api::Errors::SlackError.new("not_in_channel") if (attempts += 1) == 1
      {}
    end
    stub_join

    assert_equal :joined, JoinSlackChannelsJob.perform_now(users(:ana).id)
    assert_equal [ { channel: "C0CBHCHK469" } ], @joins
    assert_equal 2, @invites.size
    assert_not_nil users(:ana).reload.slack_channels_joined_at
  end

  test "when the bot can't join (a missing scope), nobody is marked and it can be tried again" do
    stub_invite("not_in_channel")
    stub_join("missing_scope")
    assert_equal :blocked, JoinSlackChannelsJob.perform_now(users(:ana).id)
    assert_equal 1, @invites.size
    assert_nil users(:ana).reload.slack_channels_joined_at
    assert_nil users(:ana).slack_channels_failed_at

    stub_invite
    assert_equal :joined, JoinSlackChannelsJob.perform_now(users(:ana).id)
    assert_not_nil users(:ana).reload.slack_channels_joined_at
  end

  test "it tries the invite only once more after joining" do
    stub_invite("not_in_channel")
    stub_join
    assert_equal :blocked, JoinSlackChannelsJob.perform_now(users(:ana).id)
    assert_equal 2, @invites.size
    assert_equal 1, @joins.size
  end

  test "a reason that won't change is recorded as a give-up" do
    stub_invite("user_is_restricted")
    assert_equal :failed, JoinSlackChannelsJob.perform_now(users(:ana).id)

    assert_nil users(:ana).reload.slack_channels_joined_at
    assert_not_nil users(:ana).slack_channels_failed_at
  end

  test "does nothing without a linked Slack" do
    stub_invite
    users(:ana).update_column(:slack_id, nil)
    assert_nil JoinSlackChannelsJob.perform_now(users(:ana).id)
    assert_empty @invites
  end
end
