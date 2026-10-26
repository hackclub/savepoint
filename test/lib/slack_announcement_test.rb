require "test_helper"
require Rails.root.join("lib/slack_announcement")

class SlackAnnouncementTest < ActiveSupport::TestCase
  Identity = Struct.new(:user_id)
  Sent = Struct.new(:channel, :ts)
  Link = Struct.new(:permalink)

  class FakeClient
    attr_reader :posts, :updates

    def initialize(permalink: true)
      @posts = []
      @updates = []
      @permalink = permalink
    end

    def auth_test = Identity.new("U0ME")

    def chat_postMessage(**options)
      @posts << options
      Sent.new(options[:channel], "123.456")
    end

    def chat_update(**options)
      @updates << options
      Sent.new(options[:channel], options[:ts])
    end

    def chat_getPermalink(channel:, message_ts:)
      raise Slack::Web::Api::Errors::SlackError, "missing_scope" unless @permalink
      Link.new("https://slack.example/p/#{channel}/#{message_ts}")
    end
  end

  BLOCKS = [
    { "type" => "header", "text" => { "type" => "plain_text", "text" => "Headline here" } },
    { "type" => "section", "text" => { "type" => "mrkdwn", "text" => "Body & more" } }
  ].freeze

  def announcement(data = { "text" => "Fallback", "blocks" => BLOCKS }) = SlackAnnouncement.new(JSON.generate(data))

  test "accepts an object, and takes the fallback from the first header in a bare array" do
    assert_equal "Fallback", announcement.text
    bare = announcement(BLOCKS)
    assert_equal "Headline here", bare.text
    assert_equal 2, bare.blocks.size
  end

  test "refuses bad files" do
    [ "not json", "{}", "[]", '{"blocks": "x", "text": "t"}', '[{"text": "no type"}]', '[{"type": "divider"}]',
      JSON.generate({ "text" => "t", "blocks" => Array.new(51) { { "type" => "divider" } } }) ].each do |source|
      assert_raises(SlackAnnouncement::Refused, source) { SlackAnnouncement.new(source) }
    end
  end

  test "the preview link round-trips the blocks" do
    url = announcement.preview_url
    assert url.start_with?("https://app.slack.com/block-kit-builder/#")
    json = CGI.unescape(url.delete_prefix("https://app.slack.com/block-kit-builder/#"))
    assert_equal({ "blocks" => BLOCKS }, JSON.parse(json))
  end

  test "refuses the wrong tool's channels and anything that is not a channel id" do
    SlackAnnouncement::REFUSED_CHANNELS.each do |channel|
      error = assert_raises(SlackAnnouncement::Refused) { SlackAnnouncement.check_channel!(channel) }
      assert_match(/refused/, error.message)
    end
    [ nil, "", "U0123ABCD", "C123", "c0123abcd", "#general" ].each do |channel|
      assert_raises(SlackAnnouncement::Refused, channel.inspect) { SlackAnnouncement.check_channel!(channel) }
    end
    assert_equal "C0123ABCD", SlackAnnouncement.check_channel!("C0123ABCD")
  end

  test "deliver! refuses a bad channel before touching the client" do
    client = FakeClient.new
    assert_raises(SlackAnnouncement::Refused) { announcement.deliver!("C0C5UHLAAP5", client:) }
    assert_empty client.posts
  end

  test "token check refuses blank and non-user tokens without showing them" do
    assert_raises(SlackAnnouncement::Refused) { SlackAnnouncement.token!("") }
    error = assert_raises(SlackAnnouncement::Refused) { SlackAnnouncement.token!("xoxb-secret-value") }
    assert_match(/not a user token/, error.message)
    assert_no_match(/secret/, error.message)
    assert_equal "xoxp-ok", SlackAnnouncement.token!("xoxp-ok")
  end

  test "deliver! posts the blocks to the channel with unfurling off and returns the permalink" do
    client = FakeClient.new
    result = announcement.deliver!("C0123ABCD", client:)
    post = client.posts.sole
    assert_equal "C0123ABCD", post[:channel]
    assert_equal BLOCKS, post[:blocks]
    assert_equal "Fallback", post[:text]
    assert_equal false, post[:unfurl_links]
    assert_equal false, post[:unfurl_media]
    assert_equal "https://slack.example/p/C0123ABCD/123.456", result
  end

  test "deliver! returns the ts when the permalink fails" do
    assert_equal "123.456", announcement.deliver!("C0123ABCD", client: FakeClient.new(permalink: false))
  end

  test "test! posts to the token owner's own DM" do
    client = FakeClient.new
    announcement.test!(client:)
    assert_equal "U0ME", client.posts.sole[:channel]
  end

  test "update! edits the message in place with the blocks and text, and returns the permalink" do
    client = FakeClient.new
    result = announcement.update!("C0123ABCD", "123.456", client:)
    update = client.updates.sole
    assert_equal({ channel: "C0123ABCD", ts: "123.456", text: "Fallback", blocks: BLOCKS }, update)
    assert_empty client.posts
    assert_equal "https://slack.example/p/C0123ABCD/123.456", result
  end

  test "update! refuses a bad channel or ts before touching the client" do
    client = FakeClient.new
    assert_raises(SlackAnnouncement::Refused) { announcement.update!("C0C5UHLAAP5", "123.456", client:) }
    [ nil, "", "123", "abc.def", "123.456; drop" ].each do |ts|
      assert_raises(SlackAnnouncement::Refused, ts.inspect) { announcement.update!("C0123ABCD", ts, client:) }
    end
    assert_empty client.updates
  end

  test "update! returns the ts when the permalink fails" do
    assert_equal "123.456", announcement.update!("C0123ABCD", "123.456", client: FakeClient.new(permalink: false))
  end
end
