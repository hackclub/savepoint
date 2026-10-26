require "test_helper"

class NudgeMessageTest < ActiveSupport::TestCase
  test "the text, then the button and a way to stop, as two tracked buttons, with no picture" do
    nudge = users(:orpheus).nudges.create!(channel: "slack", kind: "bandit", arm: "progress", text: "you're 35% of the way to a prize.")
    section, actions = Nudge::Message.new(nudge).blocks

    assert_equal [ "section", "actions" ], [ section[:type], actions[:type] ]
    assert_equal "you're 35% of the way to a prize.", section.dig(:text, :text)
    assert_equal [ "see your progress", "stop these messages" ], actions[:elements].map { |button| button.dig(:text, :text) }
    assert_equal [ "#{Rails.configuration.x.app_url}/n/#{nudge.token}", "#{Rails.configuration.x.app_url}/n/#{nudge.token}/stop" ],
                 actions[:elements].map { |button| button[:url] }
  end
end
