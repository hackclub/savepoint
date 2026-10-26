require "test_helper"

class NudgeStatsTest < ActiveSupport::TestCase
  test "didn't work is the scored ones that didn't, which isn't the same as the DMs that failed" do
    user = users(:orpheus)
    [ 1, 1, 0, Nudge::OPT_OUT_PENALTY ].each { |reward| user.nudges.create!(kind: "bandit", bucket: "lapsed", arm: "pledge", delivered: true, sent_at: 1.day.ago, reward:) }
    user.nudges.create!(kind: "bandit", bucket: "lapsed", arm: "pledge", delivered: true, sent_at: 1.hour.ago)
    user.update!(slack_dm_failed_at: 1.hour.ago, slack_dm_error: "user_disabled")

    stats = Nudge::Stats.new
    totals = stats.totals

    assert_equal [ 5, 4, 2, 2 ], [ totals.sent, totals.scored, totals.worked, totals.didnt_work ]
    assert_not_respond_to totals, :failed
    assert_equal 1, stats.failed_dms
  end
end
