require "test_helper"

class NpsStatsTest < ActiveSupport::TestCase
  setup do
    @now = Time.utc(2026, 10, 24, 12)
    @admins = Rails.configuration.x.admin_slack_ids
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  def answer(user, score, at: @now - 1.hour)
    NpsResponse.create!(user:, source: "daily", score:, doing_well: "a", improve: "b", created_at: at)
  end

  test "NPS is promoters minus detractors, by each person's latest answer" do
    answer(users(:orpheus), 2, at: @now - 3.days)
    answer(users(:orpheus), 10)
    answer(users(:ana), 5)
    week = NpsStats.new(now: @now).last_7_days
    assert_equal [ 1, 0, 1 ], [ week.promoters, week.passives, week.detractors ]
    assert_equal 0, week.nps
  end

  test "no answers, no NPS, and answers from the list of admins are left out" do
    assert_nil NpsStats.new(now: @now).last_7_days.nps
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    answer(users(:orpheus), 10)
    assert_not NpsStats.new(now: @now).any?
    answer(users(:ana), 9)
    assert_equal 100, NpsStats.new(now: @now).last_7_days.nps
  end
end
