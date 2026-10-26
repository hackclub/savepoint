require "test_helper"
require Rails.root.join("lib/slack_demo")

class SlackDemoTest < ActiveSupport::TestCase
  Posted = Struct.new(:channel, :text, :blocks)
  Response = Struct.new(:channel)

  class FakeClient
    attr_reader :posts

    def initialize(dm_channel: "D123")
      @dm_channel = dm_channel
      @posts = []
    end

    # Like Slack: a post to a user ID lands in that user's DM and the response names it.
    def chat_postMessage(channel:, text:, blocks: nil, **)
      @posts << Posted.new(channel, text, blocks)
      Response.new(channel.start_with?("U") ? @dm_channel : channel)
    end
  end

  test "refuses a missing id, a channel and a non-user id" do
    [ nil, "", "C0123ABCD", "G0123ABCD", "D0123ABCD", "#general", "u0123abcd" ].each do |to|
      assert_raises(SlackDemo::Refused, to.inspect) { SlackDemo.check_target!(to) }
    end
    assert_equal "U0123ABCD", SlackDemo.check_target!("U0123ABCD")
  end

  test "deliver! posts the first label to the user ID, then everything to the DM it lands in" do
    client = FakeClient.new
    demo = SlackDemo.new("U0123ABCD", client:, pause: 0)

    assert_equal demo.messages.size, demo.deliver!
    assert_equal "U0123ABCD", client.posts.first.channel
    assert_equal [ "D123" ], client.posts.drop(1).map(&:channel).uniq
    assert_equal demo.messages.size * 2, client.posts.size
    assert_match(/\A— demo 1\/#{demo.messages.size}: /, client.posts.first.text)
    assert_nil client.posts.first.blocks
    assert client.posts.second.blocks.present?
  end

  test "deliver! stops after the first post when Slack does not answer with a DM" do
    client = FakeClient.new(dm_channel: "C999")
    assert_raises(SlackDemo::Refused) { SlackDemo.new("U0123ABCD", client:, pause: 0).deliver! }
    assert_equal 1, client.posts.size
  end

  test "deliver! refuses a channel id before touching the client" do
    client = FakeClient.new
    assert_raises(SlackDemo::Refused) { SlackDemo.new("C0123ABCD", client:, pause: 0).deliver! }
    assert_empty client.posts
  end

  test "builds every message without saving anything" do
    before = [ User.count, Nudge.count, Project.count ]
    demo = SlackDemo.new("U0123ABCD")
    assert_operator demo.messages.size, :>=, 60
    assert_equal before, [ User.count, Nudge.count, Project.count ]
    assert_no_match(/clippy|wrong/i, demo.preview)
  end
end
