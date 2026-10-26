require "test_helper"
require_relative "../support/admin_mcp_helpers"

class AdminSummaryTest < ActiveSupport::TestCase
  include AdminMcpHelpers

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    create_insights_views
    travel_to Time.utc(2026, 10, 24, 20)
    User.update_all(created_at: Time.utc(2026, 10, 23, 9))
    @ana = users(:ana)
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 23), coded_seconds: 5 * 3600)
    users(:orpheus).streak_activities.create!(activity_date: Date.new(2026, 10, 23), coded_seconds: 9 * 3600)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "sign-ups and DAU leave out admins" do
    summary = AdminSummary.new.to_h

    assert_equal User.where.not(slack_id: "U0ORPHEUS").count, summary[:signups]
    assert_equal 0, summary[:signups_today]
    assert_equal [ 1, Date.new(2026, 10, 23) ], summary.values_at(:dau, :dau_date)
  end

  test "daily has a row for each finished day, for participants only, with empty days at 0" do
    travel_to Time.utc(2026, 10, 26, 20)
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 90 * 60)
    users(:orpheus).streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 3 * 3600)
    @ana.update_columns(created_at: Time.utc(2026, 10, 24, 23, 59))
    daily = AdminSummary.new.daily.index_by { |row| row[:date] }

    assert_equal (Program::HACKATIME_START..Date.new(2026, 10, 25)).to_a, daily.keys, "finished days only: today is still filling in"
    assert_equal({ date: Date.new(2026, 10, 24), dau: 1, states: { new: 0, current: 1, reactivated: 0, resurrected: 0 }, signups: 1, hours: 1.5 }, daily[Date.new(2026, 10, 24)])
    assert_equal({ date: Date.new(2026, 10, 25), dau: 0, states: { new: 0, current: 0, reactivated: 0, resurrected: 0 }, signups: 0, hours: 0.0 }, daily[Date.new(2026, 10, 25)])
    assert_equal [ 1, 5.0, User.participants.where.not(id: @ana.id).count ], daily[Date.new(2026, 10, 23)].values_at(:dau, :hours, :signups), "the admin's 9 hours and sign-up are left out"
  end

  test "the summary carries the participants' funnel, and its cache key is v2" do
    summary = AdminSummary.new.to_h

    assert_equal User.participants.count, summary.dig(:participant_funnel, :participants)
    assert_equal ParticipantFunnel::STEPS.map(&:first), summary.dig(:participant_funnel, :steps).map { |step| step[:key] }
    assert_equal AdminSummary.new.daily, summary[:daily]
    assert_equal %i[pace prize_spend sign_up_day ship_flow nudge_results], %i[pace prize_spend sign_up_day ship_flow nudge_results].select { |key| summary.key?(key) }
  end

  test "hours not in a ship yet are unapproved, and an admin's are left out" do
    assert_equal({ unapproved_hours: 5.0, pending_hours: 0.0, approved_hours: 0.0 }, AdminSummary.new.funnel)
  end

  test "a ship in review is pending for what it adds to the last approved ship" do
    ship(2.0, status: "approved", approved_hours: 1.5)
    ship(3.5)
    ship(4.0, project: projects(:orpheus))

    assert_equal({ unapproved_hours: 1.5, pending_hours: 1.5, approved_hours: 1.5 }, AdminSummary.new.funnel)
  end

  test "unapproved never goes below 0 when a ship holds more than Hackatime shows" do
    ship(6.0, status: "approved")

    assert_equal({ unapproved_hours: 0.0, pending_hours: 0.0, approved_hours: 6.0 }, AdminSummary.new.funnel)
  end

  private
    def ship(hours, status: "in_review", approved_hours: nil, project: projects(:ana))
      project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                            repo_url: "https://example.com/repo", demo_url: "https://example.com/demo", hours:, status:, approved_hours:,
                            screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
end
