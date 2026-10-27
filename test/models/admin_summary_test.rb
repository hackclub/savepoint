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
    assert_equal 0, summary[:dau], "ana built yesterday, not today"
  end

  def bucket(user, minutes_ago, seconds, held: false)
    CodedBucket.create!(user:, bucket_at: CodedBucket.floor(minutes_ago.minutes.ago), seconds: held ? 0 : seconds, unconfirmed_seconds: held ? seconds : 0)
  end

  test "D-092: DAU is the participants who built a minute or more today, Eastern midnight to now" do
    dee = User.create!(hca_id: "ident!dee", first_name: "Dee")
    eve = User.create!(hca_id: "ident!eve", first_name: "Eve")
    bucket(@ana, 3 * 60, Growth::ACTIVE_SECONDS)
    bucket(dee, 60, Growth::ACTIVE_SECONDS - 30)
    bucket(users(:orpheus), 60, 3600)
    bucket(eve, 21 * 60, 3600)
    summary = AdminSummary.new.to_h

    assert_equal 1, summary[:dau], "ana's 60 s at 17:00 UTC counts; dee's 30 s, the admin's hour and eve's hour at 23:00 UTC yesterday (19:00 ET) don't"
    assert_nil summary[:dau_on_site], "no visit recorded yet"
  end

  test "D-092: the tile resets at midnight Eastern, so 03:59 UTC is still the previous day" do
    travel_to Time.utc(2026, 10, 25, 3, 59) do
      bucket(@ana, 4, 600)
      assert_equal 1, AdminSummary.new.to_h[:dau], "03:55 UTC is 23:55 ET on the 24th, in the 24th's day"
      assert_equal Date.new(2026, 10, 24), AdminSummary.new.to_h[:today_row][:date]
    end

    travel_to Time.utc(2026, 10, 25, 4, 1) do
      assert_equal 0, AdminSummary.new.to_h[:dau], "00:01 ET on the 25th: a new day with nothing in it"
      assert_equal Date.new(2026, 10, 25), AdminSummary.new.to_h[:today_row][:date]
      bucket(@ana, 1, 300)
      summary = AdminSummary.new.to_h
      assert_equal [ 1, 1 ], [ summary[:dau], summary[:today_row][:dau] ]
    end
  end

  test "D-092: several pieces today add up to a minute" do
    bucket(@ana, 120, 30)
    bucket(@ana, 10, 30)

    assert_equal 1, AdminSummary.new.to_h[:dau]
  end

  test "D-084: DAU counts confirmed builders only and says how many more are unconfirmed" do
    dee = User.create!(hca_id: "ident!dee", first_name: "Dee")
    bucket(@ana, 30, 600)
    bucket(dee, 30, 600, held: true)
    bucket(users(:orpheus), 30, 600, held: true)
    summary = AdminSummary.new.to_h

    assert_equal 1, summary[:dau]
    assert_equal 1, summary[:dau_unconfirmed], "dee's held ten minutes; the admin's don't count"
  end

  test "the site count beside today's DAU is today's, 0 once visits are being recorded" do
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 600)
    SiteDay.create!(user: @ana, date: Date.new(2026, 10, 23))
    assert_equal 0, AdminSummary.new.to_h[:dau_on_site]
    SiteDay.create!(user: @ana, date: Date.new(2026, 10, 24))
    assert_equal 1, AdminSummary.new.to_h[:dau_on_site]
  end

  test "today's row is the day so far: builders split by state, sign-ups, hours, and the finished days stay without it" do
    dee = User.create!(hca_id: "ident!dee", first_name: "Dee", created_at: Time.utc(2026, 10, 24, 9))
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 1800)
    dee.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 1800)
    bucket(@ana, 30, 1800)
    bucket(dee, 30, 1800)
    summary = AdminSummary.new.to_h

    assert_equal Date.new(2026, 10, 24), summary[:today_row][:date]
    assert_equal({ new: 1, current: 1, returning: 0 }, summary[:today_row][:states])
    assert_equal summary[:dau], summary[:today_row][:dau], "D-092: the last column of the charts is the tile's number"
    assert_equal [ 1, 1.0 ], summary[:today_row].values_at(:signups, :hours)
    assert_equal Date.new(2026, 10, 23), summary[:daily].last[:date], "daily is finished days only, so averages leave today out"
    assert_equal Date.new(2026, 10, 24), summary[:sign_up_today][:date]
    assert_equal Date.new(2026, 10, 23), summary[:sign_up_day].last[:date]
  end

  test "there is no row for today outside the days of Save Point" do
    travel_to Program::DATES.end + 3
    assert_nil AdminSummary.new.to_h[:today_row]
    assert_nil AdminSummary.new.to_h[:sign_up_today]
  end

  test "daily says how many builders also opened the site, and nothing before the first recorded day" do
    travel_to Time.utc(2026, 10, 27, 20)
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 25), coded_seconds: 30 * 60)
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 26), coded_seconds: 30 * 60)
    users(:orpheus).streak_activities.create!(activity_date: Date.new(2026, 10, 26), coded_seconds: 30 * 60)
    SiteDay.create!(user: @ana, date: Date.new(2026, 10, 26))
    SiteDay.create!(user: users(:orpheus), date: Date.new(2026, 10, 26))
    summary = AdminSummary.new
    daily = summary.daily.index_by { |row| row[:date] }

    assert_nil daily[Date.new(2026, 10, 25)][:on_site], "before the first recorded day it's unknown, not 0"
    assert_equal 1, daily[Date.new(2026, 10, 26)][:on_site], "the admin's visit is left out"
    assert_equal({ Date.new(2026, 10, 26) => 1 }, summary.site_days)
  end

  test "site_days is empty until a visit has been recorded" do
    assert_equal({}, AdminSummary.new.site_days)
  end

  test "daily has a row for each finished day, for participants only, with empty days at 0" do
    travel_to Time.utc(2026, 10, 26, 20)
    @ana.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 90 * 60)
    users(:orpheus).streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 3 * 3600)
    @ana.update_columns(created_at: Time.utc(2026, 10, 24, 23, 59))
    daily = AdminSummary.new.daily.index_by { |row| row[:date] }

    assert_equal (Program::HACKATIME_START..Date.new(2026, 10, 25)).to_a, daily.keys, "finished days only: today is still filling in"
    assert_equal({ date: Date.new(2026, 10, 24), on_site: nil, dau: 1, states: { new: 0, current: 1, returning: 0 }, signups: 1, hours: 1.5 }, daily[Date.new(2026, 10, 24)])
    assert_equal({ date: Date.new(2026, 10, 25), on_site: nil, dau: 0, states: { new: 0, current: 0, returning: 0 }, signups: 0, hours: 0.0 }, daily[Date.new(2026, 10, 25)])
    assert_equal [ 1, 5.0, User.participants.where.not(id: @ana.id).count ], daily[Date.new(2026, 10, 23)].values_at(:dau, :hours, :signups), "the admin's 9 hours and sign-up are left out"
  end

  test "daily splits each day's builders into new, built yesterday too, and back after days off, and they sum to the DAU" do
    travel_to Time.utc(2026, 10, 27, 20)
    [ 24, 26 ].each { |day| @ana.streak_activities.create!(activity_date: Date.new(2026, 10, day), coded_seconds: 10 * 60) }
    dee = User.create!(hca_id: "ident!dee", first_name: "Dee")
    [ 25, 26 ].each { |day| dee.streak_activities.create!(activity_date: Date.new(2026, 10, day), coded_seconds: 10 * 60) }
    eve = User.create!(hca_id: "ident!eve", first_name: "Eve")
    eve.streak_activities.create!(activity_date: Date.new(2026, 10, 26), coded_seconds: 10 * 60)
    daily = AdminSummary.new.daily.index_by { |row| row[:date] }

    assert_equal({ new: 1, current: 1, returning: 1 }, daily[Date.new(2026, 10, 26)][:states], "eve is new, dee built the day before too, ana was away on the 25th")
    assert_equal({ new: 1, current: 0, returning: 0 }, daily[Date.new(2026, 10, 25)][:states])
    assert_equal({ new: 0, current: 1, returning: 0 }, daily[Date.new(2026, 10, 24)][:states])
    assert(daily.values.all? { |row| row[:states].values.sum == row[:dau] })
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
