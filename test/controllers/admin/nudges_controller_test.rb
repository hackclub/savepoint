require "test_helper"

class Admin::NudgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]

    ana = users(:ana)
    ana.nudges.create!(kind: "bandit", bucket: "lapsed", arm: "tiny_step", text: "20 minutes, one small feature.",
                       propensity: 0.4, delivered: true, sent_at: 8.hours.ago, reward: 1, clicks: 1, clicked_at: 7.hours.ago)
    ana.nudges.create!(kind: "bandit", bucket: "lapsed", arm: "social", text: "people are building games today.", propensity: 0.2,
                       delivered: true, sent_at: 7.hours.ago, reward: Nudge::OPT_OUT_PENALTY, opted_out_at: 7.hours.ago)
    ana.nudges.create!(kind: "bandit", bucket: "lapsed", arm: "tiny_step", holdout: true, text: "one small task.",
                       propensity: 1.0, delivered: true, sent_at: 1.hour.ago)
    ana.nudges.create!(kind: "milestone", arm: "first_session", text: "first session logged.", delivered: true, sent_at: 2.hours.ago)
    ana.nudges.create!(kind: "setup", arm: "repo", text: "add your repo link.", delivered: true, sent_at: 9.hours.ago, reward: 1)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see how nudges are doing and what the bandit thinks of each arm" do
    sign_in_as(users(:orpheus))
    get admin_nudges_path

    assert_response :success
    assert_select ".admin__tile", text: /Sent\s*5/
    assert_select ".admin__tile", text: /Worked\s*67%\s*2 of 3 scored/
    assert_select "h2", "Lapsed"
    assert_select "h2", "Zero hours"
    assert_select "tr[data-leading] th", "Tiny step"
    assert_select "tr", text: /Holdout\s*1/
    assert_select ".admin__table--recent tbody tr", 5
    assert_select ".admin__table--recent td", text: "stopped"
    assert_select ".admin__table--recent td", text: "did it"
    assert_select "tr", text: /Repo\s*setup\s*1\s*.*100%/
  end

  test "nobody else can see it" do
    get admin_nudges_path
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_nudges_path
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id)
      post "/auth/hackclub"
      follow_redirect!
    end
end
