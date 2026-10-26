require "test_helper"

class NudgeLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @nudge = users(:orpheus).nudges.create!(channel: "slack", kind: "bandit", arm: "progress",
                                            text: "you're 35% of the way to a prize.")
  end

  test "the button counts the click and goes where it said" do
    get nudge_link_path(@nudge.token)
    assert_redirected_to "#{Rails.configuration.x.app_url}/project"

    get nudge_link_path(@nudge.token)
    @nudge.reload
    assert_equal 2, @nudge.clicks
    assert @nudge.clicked_at
  end

  test "a social nudge's button goes to the project, since Save Point has no Slack channel yet" do
    @nudge.update!(arm: "social")
    get nudge_link_path(@nudge.token)
    assert_redirected_to "#{Rails.configuration.x.app_url}/project"
  end

  test "a link that doesn't exist goes home" do
    get nudge_link_path("nope")
    assert_redirected_to root_path
  end

  test "stopping asks first, since links get opened ahead of time" do
    get nudge_stop_path(@nudge.token)

    assert_response :success
    assert_select "h1", "Stop the Slack messages?"
    assert_nil users(:orpheus).reload.slack_muted_at
  end

  test "stopping mutes the bot and counts against that nudge, and you can change your mind" do
    post nudge_stop_path(@nudge.token)
    follow_redirect!
    assert_select "h1", "We won't message you on Slack anymore."
    assert users(:orpheus).reload.slack_muted_at
    assert @nudge.reload.opted_out_at

    delete nudge_stop_path(@nudge.token)
    follow_redirect!
    assert_select "h1", "Stop the Slack messages?"
    assert_nil users(:orpheus).reload.slack_muted_at
    assert_nil @nudge.reload.opted_out_at
  end
end
