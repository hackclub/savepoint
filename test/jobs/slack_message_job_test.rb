require "test_helper"

class SlackMessageJobTest < ActiveJob::TestCase
  setup do
    @configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, true
    @post = Slack::Web::Client.instance_method(:chat_postMessage)
    @join = Slack::Web::Client.instance_method(:conversations_join)
    @posts, @joins = [], []
  end

  teardown do
    Rails.configuration.x.slack_configured = @configured
    Slack::Web::Client.define_method(:chat_postMessage, @post)
    Slack::Web::Client.define_method(:conversations_join, @join)
  end

  # chat.postMessage raises each error in turn (then succeeds), and every attempt is recorded. Joins are recorded too.
  def stub_slack(post_errors: [], join_error: nil)
    posts, joins, errors = @posts, @joins, post_errors.dup
    Slack::Web::Client.define_method(:chat_postMessage) do |**args|
      posts << args
      error = errors.shift
      raise Slack::Web::Api::Errors::SlackError.new(error) if error
      {}
    end
    Slack::Web::Client.define_method(:conversations_join) do |**args|
      joins << args
      raise Slack::Web::Api::Errors::SlackError.new(join_error) if join_error
      {}
    end
  end

  test "posts to a channel" do
    stub_slack
    SlackMessageJob.perform_now("C0CBHCHK469", "hi")

    assert_equal [ "C0CBHCHK469" ], @posts.map { _1[:channel] }
    assert_empty @joins
  end

  test "when the bot isn't in the channel, it joins and posts again" do
    stub_slack(post_errors: [ "not_in_channel" ])
    SlackMessageJob.perform_now("C0CBHCHK469", "hi")

    assert_equal [ { channel: "C0CBHCHK469" } ], @joins
    assert_equal 2, @posts.size
  end

  test "it posts only once more after joining" do
    stub_slack(post_errors: [ "not_in_channel", "not_in_channel" ])
    SlackMessageJob.perform_now("C0CBHCHK469", "hi")

    assert_equal 1, @joins.size
    assert_equal 2, @posts.size
  end

  test "when the bot can't join, the post is dropped and logged" do
    stub_slack(post_errors: [ "not_in_channel" ], join_error: "missing_scope")
    assert_nothing_raised { SlackMessageJob.perform_now("C0CBHCHK469", "hi") }

    assert_equal 1, @posts.size
    assert_equal 1, @joins.size
  end

  test "a DM never joins anything" do
    stub_slack(post_errors: [ "not_in_channel" ])
    SlackMessageJob.perform_now("U0ANA", "hi")

    assert_empty @joins
    assert_equal 1, @posts.size
  end
end
