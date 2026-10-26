require "test_helper"

class SlackProfileJobTest < ActiveJob::TestCase
  setup do
    @configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, true
    @users_info = Slack::Web::Client.instance_method(:users_info)
  end

  teardown do
    Rails.configuration.x.slack_configured = @configured
    Slack::Web::Client.define_method(:users_info, @users_info)
  end

  def slack_profile(display_name:, real_name: "Ana Lovelace", tz: "Europe/London", name: "ana.l", **picture)
    user = Slack::Messages::Message.new(user: { tz:, name:, real_name:, profile: { display_name:, real_name: }.merge(picture) })
    Slack::Web::Client.define_method(:users_info) { |**| user }
  end

  test "takes your Slack display name, and your timezone if your browser hasn't said" do
    slack_profile(display_name: " pixel ana ")
    SlackProfileJob.perform_now(users(:ana).id)

    assert_equal "pixel ana", users(:ana).reload.slack_display_name
    assert_equal "Europe/London", users(:ana).timezone
    assert_equal "ana.l", users(:ana).slack_username
  end

  test "with no display name, your Slack username stands in, never your real name" do
    users(:ana).update!(timezone: "Asia/Tokyo")
    slack_profile(display_name: "")
    SlackProfileJob.perform_now(users(:ana).id)

    assert_nil users(:ana).reload.slack_display_name
    assert_equal "ana.l", users(:ana).public_name
    assert_equal "Asia/Tokyo", users(:ana).timezone, "the browser's timezone wins"
  end

  test "takes your custom Slack picture" do
    slack_profile(display_name: "pixel ana", is_custom_image: true, image_192: "https://avatars.slack-edge.com/ana_192.png",
                  image_512: "https://avatars.slack-edge.com/ana_512.png")
    SlackProfileJob.perform_now(users(:ana).id)

    assert_equal "https://avatars.slack-edge.com/ana_512.png", users(:ana).reload.slack_avatar_url
  end

  test "with no custom Slack picture, none is stored, so Slack's placeholder never shows" do
    users(:ana).update!(slack_avatar_url: "https://avatars.slack-edge.com/old.png")
    slack_profile(display_name: "pixel ana", is_custom_image: false, image_512: "https://a.slack-edge.com/default.png")
    SlackProfileJob.perform_now(users(:ana).id)
    assert_nil users(:ana).reload.slack_avatar_url

    slack_profile(display_name: "pixel ana", image_512: "https://a.slack-edge.com/default.png")
    SlackProfileJob.perform_now(users(:ana).id)
    assert_nil users(:ana).reload.slack_avatar_url
  end
end
