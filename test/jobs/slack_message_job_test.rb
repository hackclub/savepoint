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

  # D-113: a banned account gets no DM from the app.
  test "a banned person's DM is dropped, one queued before the ban too" do
    stub_slack
    assert_enqueued_jobs 1 do
      SlackMessageJob.perform_later("U0ANA", "queued while Ana wasn't banned")
    end
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    perform_enqueued_jobs
    SlackMessageJob.perform_now("U0ANA", "sent after", link: [ "Open Save Point", "https://savepoint.example/project" ])

    assert_empty @posts
    assert_empty @joins
  end

  test "a dropped DM isn't noted as the bot's latest to them" do
    stub_slack
    users(:ana).ban!("Fraud.", by: users(:orpheus))
    SlackMessageJob.perform_now("U0ANA", "hi")

    assert_nil users(:ana).reload.slack_dmed_at
  end

  test "it still posts to channels, and DMs people who aren't banned, whoever is" do
    stub_slack
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    SlackMessageJob.perform_now("C0CBHCHK469", "a shoutout")
    SlackMessageJob.perform_now("U0ORPHEUS", "hi")

    assert_equal [ "C0CBHCHK469", "U0ORPHEUS" ], @posts.map { _1[:channel] }
    assert_not_nil users(:orpheus).reload.slack_dmed_at
  end
end
