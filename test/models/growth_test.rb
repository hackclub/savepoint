require "test_helper"

class GrowthTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 11, 1)

  test "sorts each builder into one state and records yesterday-to-today moves" do
    built("new", 0)
    built("built_yesterday_too", 1, 0)
    built("skipped_today", 1)
    built("back_after_days_off", 3, 0)
    built("gone", 3)
    built("too_short", 0, seconds: Growth::ACTIVE_SECONDS - 1)
    built("later", -1)

    day = Growth.new(today: DAY + 1).days.last

    assert_equal DAY, day.date
    assert_equal({ "new" => 1, "current" => 1, "returning" => 1, "at_risk" => 1, "lapsed" => 1 }, day.counts)
    assert_equal 3, day.dau
    assert_equal(
      { "new" => { "current" => 1, "at_risk" => 1 }, "lapsed" => { "lapsed" => 1, "returning" => 1 } },
      day.transitions
    )
    assert_in_delta 0.5, day.rate("nurr")
    assert_in_delta 0.5, day.rate("days_off")
    assert_nil day.rate("curr"), "nobody had built two days running yesterday"
  end

  test "the three groups that built on a day always sum to its DAU" do
    built("first_timer", 0)
    built("on_a_roll", 2, 1, 0)
    built("back_after_two_days_off", 4, 0)

    day = Growth.new(today: DAY + 1).days.last

    assert_equal [ "new", "current", "returning" ], Growth::ACTIVE_STATES
    assert_equal [ 1, 1, 1 ], Growth::ACTIVE_STATES.map { |state| day.count_for(state) }
    assert_equal 3, day.dau
    assert_equal day.dau, Growth::ACTIVE_STATES.sum { |state| day.count_for(state) }
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
    assert_equal 1, stats[:today][:at_risk]
    assert_nil stats[:projections]["word_of_mouth"], "nobody's been current a day yet, so there's nothing to project from"
    built("regular", 2, 1, 0)
    assert_equal Program::DATES.end - DAY, Growth.new(today: DAY + 1).to_h[:projections]["word_of_mouth"][:horizon_days]
    assert_nil Growth.new(today: Program::DATES.begin).latest, "nothing's finished on the first day"
    assert_nil Growth.new(today: Program::DATES.end + 1).to_h[:projections]["flat"], "nothing left to project"
  end

  test "the rates shown pool several days" do
    built("stayed", 1, 0)
    built("left", 1)
    built("stayed_earlier", 5, 4)
    built("left_earlier", 5)
    built("kept_on", 2, 1, 0)

    rates = Growth.new(today: DAY + 1).pooled_rates.last
    assert_equal DAY, rates[:date]
    assert_in_delta 0.6, rates[:nurr], 0.001, "three of the five newcomers this week built again the next day"
    assert_in_delta 0.5, rates[:curr], 0.001, "kept_on kept on; stayed_earlier didn't"
    assert_equal 0.0, rates[:days_off], "nobody came back after days off"
  end

  test "states by what someone did on and before the day" do
    dates = [ DAY - 8, DAY - 7, DAY - 3, DAY ]

    assert_nil Growth.state_on(dates, DAY - 9)
    assert_equal "new", Growth.state_on(dates, DAY - 8)
    assert_equal "current", Growth.state_on(dates, DAY - 7), "built the day before too"
    assert_equal "at_risk", Growth.state_on(dates, DAY - 6), "built yesterday, not today"
    assert_equal "lapsed", Growth.state_on(dates, DAY - 5)
    assert_equal "returning", Growth.state_on(dates, DAY - 3), "built before, but not the day before"
    assert_equal "returning", Growth.state_on(dates, DAY)
    assert_equal "lapsed", Growth.state_on(dates, DAY - 1), "two days gone is still lapsed, never a month"
  end

  private
    # Someone who built on each of `days_ago` days before DAY.
    def built(name, *days_ago, seconds: Growth::ACTIVE_SECONDS)
      user = User.create!(hca_id: "ident!growth_#{name}", first_name: name)
      days_ago.each { |ago| user.streak_activities.create!(activity_date: DAY - ago, coded_seconds: seconds) }
      user
    end
end
