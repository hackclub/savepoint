require "test_helper"

class GrowthTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 11, 1)

  test "sorts each builder into one state and records yesterday-to-today moves" do
    built("new", 0)
    built("current", 3, 1, 0)
    built("at_risk_wau", 2)
    built("wau_lost", 7)
    built("reactivated", 9, 0)
    built("too_short", 0, seconds: 4 * 60)
    built("later", -1)

    day = Growth.new(today: DAY + 1).days.last

    assert_equal DAY, day.date
    assert_equal({ "new" => 1, "current" => 1, "at_risk_wau" => 1, "at_risk_mau" => 1, "reactivated" => 1 }, day.counts)
    assert_equal 3, day.dau
    assert_equal 4, day.wau
    assert_equal 5, day.mau
    assert_equal(
      { "current" => { "current" => 1 }, "at_risk_wau" => { "at_risk_wau" => 1, "at_risk_mau" => 1 }, "at_risk_mau" => { "reactivated" => 1 } },
      day.transitions
    )
    assert_in_delta 0.5, day.rate("wau_loss")
    assert_equal 1.0, day.rate("curr")
    assert_nil day.rate("nurr"), "nobody was new yesterday"
  end

  test "only finished days of Save Point are modelled, and today is kept apart, as far as it's got" do
    built("early", 0)
    built("today", -1)

    growth = Growth.new(today: DAY + 1)
    assert_equal Program::HACKATIME_START..DAY, growth.days.first.date..growth.days.last.date
    assert_equal 1, growth.latest.dau

    stats = growth.to_h
    assert_equal Program::DATES.count, stats[:days].size
    assert_equal [ 1, 1 ], stats[:days].find { |row| row[:date] == DAY }.values_at(:dau, :new)
    assert_equal [ true, nil ], stats[:days].find { |row| row[:date] == DAY + 1 }.values_at(:future, :dau)
    assert_equal Program::DATES.count, stats[:rates].size
    assert_equal [ 1, 1 ], stats[:today].values_at(:dau, :new), "the person building today, so far"
    assert_equal 1, stats[:today][:at_risk_wau]
    assert_nil stats[:projections]["word_of_mouth"], "nobody's been current a day yet, so there's nothing to project from"
    built("regular", 2, 1, 0)
    assert_equal Program::DATES.end - DAY, Growth.new(today: DAY + 1).to_h[:projections]["word_of_mouth"][:horizon_days]
    assert_nil Growth.new(today: Program::DATES.begin).latest, "nothing's finished on the first day"
    assert_nil Growth.new(today: Program::DATES.end + 1).to_h[:projections]["flat"], "nothing left to project"
  end

  test "the rates shown pool a week" do
    built("stayed", 1, 0)
    built("left", 1)
    built("stayed_earlier", 5, 4)
    built("left_earlier", 5)
    built("kept_on", 2, 1, 0)

    rates = Growth.new(today: DAY + 1).pooled_rates.last
    assert_equal DAY, rates[:date]
    assert_in_delta 0.6, rates[:nurr], 0.001, "three of the five newcomers this week built again the next day"
    assert_in_delta 0.5, rates[:curr], 0.001, "kept_on kept on; stayed_earlier didn't"
    assert_nil rates[:surr]
  end

  test "states by when someone last built" do
    dates = [ DAY - 40, DAY - 10, DAY - 3, DAY ]

    assert_nil Growth.state_on(dates, DAY - 41)
    assert_equal "new", Growth.state_on(dates, DAY - 40)
    assert_equal "at_risk_wau", Growth.state_on(dates, DAY - 39)
    assert_equal "at_risk_mau", Growth.state_on(dates, DAY - 33)
    assert_equal "at_risk_mau", Growth.state_on(dates, DAY - 11), "29 days on is still the month"
    assert_equal "dormant", Growth.state_on([ DAY - 40 ], DAY - 10)
    assert_equal "resurrected", Growth.state_on(dates, DAY - 10)
    assert_equal "current", Growth.state_on(dates, DAY)
    assert_equal "reactivated", Growth.state_on([ DAY - 10, DAY ], DAY)
  end

  private
    # Someone who built on each of `days_ago` days before DAY.
    def built(name, *days_ago, seconds: Growth::ACTIVE_SECONDS)
      user = User.create!(hca_id: "ident!growth_#{name}", first_name: name)
      days_ago.each { |ago| user.streak_activities.create!(activity_date: DAY - ago, coded_seconds: seconds) }
      user
    end
end
