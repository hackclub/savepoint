require "test_helper"

class SlackBotTest < ActiveSupport::TestCase
  setup do
    @configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, true
    @post = Slack::Web::Client.instance_method(:chat_postMessage)
    @posts = []
    posts = @posts
    Slack::Web::Client.define_method(:chat_postMessage) do |**args|
      posts << args
      { "channel" => "D0DM", "ts" => "1.0" }
    end
  end

  teardown do
    Rails.configuration.x.slack_configured = @configured
    Slack::Web::Client.define_method(:chat_postMessage, @post)
  end

  test "a DM goes to the Slack ID it's for" do
    assert SlackBot.dm("U0ANA", text: "hi", blocks: [])

    assert_equal [ "U0ANA" ], @posts.map { _1[:channel] }
  end

  test "a banned account gets no DM: nothing is sent, nothing is called back, and it returns nil (D-113)" do
    users(:ana).ban!("Fraud.", by: users(:orpheus))
    errors = []

    assert_nil SlackBot.dm("U0ANA", text: "hi", blocks: [], on_error: ->(code) { errors << code })

    assert_empty @posts
    assert_empty errors, "a skipped DM isn't a Slack error"
  end

  test "banning someone stops their DMs and leaves everyone else's" do
    SlackBot.dm("U0ANA", text: "before", blocks: [])
    users(:ana).ban!("Fraud.", by: users(:orpheus))
    SlackBot.dm("U0ANA", text: "after", blocks: [])
    SlackBot.dm("U0ORPHEUS", text: "to someone else", blocks: [])

    assert_equal [ "U0ANA", "U0ORPHEUS" ], @posts.map { _1[:channel] }
    assert_equal [ "before", "to someone else" ], @posts.map { _1[:text] }
  end

  test "a skipped DM logs one line saying so, whether or not Slack is set up" do
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    [ true, false ].each do |configured|
      Rails.configuration.x.slack_configured = configured
      logged = capture_log { SlackBot.dm("U0ANA", text: "hi", blocks: []) }

      assert_equal "Slack DM to U0ANA skipped: the account is banned\n", logged
    end
    assert_empty @posts
  end

  test "a blank Slack ID, and one that's no account's or a channel's, isn't a banned account's" do
    User.create!(hca_id: "ident!nobody", email: "nobody@hackclub.com", name: "No Slack", first_name: "No", slack_id: nil, banned_at: Time.current)
    users(:ana).ban!("Fraud.", by: users(:orpheus))

    assert_not SlackBot.banned_recipient?(nil)
    assert_not SlackBot.banned_recipient?("")
    assert_not SlackBot.banned_recipient?("U0NOBODY")
    assert_not SlackBot.banned_recipient?("C0CBHCHK469")
    assert_not SlackBot.banned_recipient?("U0ORPHEUS")
    assert SlackBot.banned_recipient?("U0ANA")
  end

  private
    # What the block writes to Rails.logger.
    def capture_log
      logged = StringIO.new
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(logged)
      yield
      logged.string
    ensure
      Rails.logger = original
    end
end
