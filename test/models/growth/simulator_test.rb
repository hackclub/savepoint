require "test_helper"

class Growth::SimulatorTest < ActiveSupport::TestCase
  test "ranks retention levers by the DAU they add" do
    levers = Growth::Simulator.new([ day ] * 3, signups: "flat", horizon: 10).levers

    assert levers.all? { |lever| lever.lift.positive? }
    assert_equal levers.map(&:lift).sort.reverse, levers.map(&:lift)
    assert_equal "curr", levers.first.rate
    assert_in_delta 0.8, levers.find { |lever| lever.rate == "curr" }.current_rate
    assert_equal 10, levers.first.daily_dau.size
  end

  test "rates the window never saw are not levers" do
    levers = Growth::Simulator.new([ day ], horizon: 10).levers.map(&:rate)

    assert_not_includes levers, "days_off"
    assert_not_includes levers, "rurr"
  end

  # Duolingo's example: 80% retention and one newcomer a day per five active builders holds DAU flat, and a
  # better retention rate then compounds.
  test "word of mouth holds a balanced DAU steady and compounds an improvement" do
    balanced = Growth::Day.new(
      date: Date.new(2026, 10, 27), counts: { "new" => 20, "current" => 80 },
      transitions: { "new" => { "current" => 16, "at_risk" => 4 }, "current" => { "current" => 64, "at_risk" => 16 } }
    )
    simulator = Growth::Simulator.new([ balanced ] * 4, horizon: 10)
    curr = simulator.levers.find { |lever| lever.rate == "curr" }

    assert simulator.word_of_mouth?
    assert_in_delta 0.2, simulator.signups_per_dau
    simulator.baseline.each { |dau| assert_in_delta 100, dau, 0.001 }
    gains = curr.daily_dau.map { |dau| dau - 100 }
    assert gains.each_cons(2).all? { |earlier, later| later > earlier }
    assert curr.cost_of_waiting.positive?
  end

  test "word of mouth makes the same improvement worth more than flat signups" do
    lift = ->(signups) { Growth::Simulator.new([ day ] * 3, signups:, horizon: 10).levers.find { |lever| lever.rate == "curr" }.lift }

    assert_operator lift.call("word_of_mouth"), :>, lift.call("flat")
  end

  # Save Point's first days: DAU 0, 3, 11, 43 and many first-time builders. Dividing by the day before's DAU
  # gave about 3 new builders per builder, and compounding that daily projected 416,247 DAU.
  test "early days with tiny DAU are not a word-of-mouth rate" do
    simulator = Growth::Simulator.new(early_days, horizon: 10)

    assert_not simulator.word_of_mouth?, "only one day had #{Growth::Simulator::MIN_DAU} builders the day before"
    assert_in_delta 32 / 11.0, simulator.signups_per_dau, 0.001, "ratio of sums over the qualifying days, not the days with DAU 0 and 3"
  end

  test "the rate is a ratio of sums, and leaves out days under the DAU floor" do
    days = [ steady(dau: 2, new: 6), steady(dau: 20, new: 2), steady(dau: 40, new: 8), steady(dau: 40, new: 4), steady(dau: 60, new: 9) ]
    simulator = Growth::Simulator.new(days, horizon: 5)

    assert simulator.word_of_mouth?
    assert_in_delta (8 + 4 + 9) / 100.0, simulator.signups_per_dau, 0.001, "(8+4+9) over (20+40+40); the DAU 2 day's 2 is left out"
  end

  test "a projection stays within twice the best day's new builders even when the rate is wild" do
    simulator = Growth::Simulator.new(early_days, horizon: 10)
    peak_new = early_days.map { |day| day.count_for("new") }.max

    assert_operator simulator.baseline_dau, :<=, 43 + 10 * Growth::Simulator::NEW_CEILING * peak_new
    assert_operator simulator.baseline_dau, :<, 5_000, "not the 416,247 of compounding the early rate"
  end

  test "a rate with fewer than the minimum builders leaving its state is not a lever" do
    levers = Growth::Simulator.new(early_days.first(3), signups: "flat", horizon: 10).levers.map(&:rate)

    assert_not_includes levers, "curr", "only a few builders have been current so far"
    assert_includes levers, "nurr"
  end

  private
    def early_days
      [
        steady(dau: 0, new: 0),
        steady(dau: 3, new: 3),
        steady(dau: 11, new: 8),
        steady(dau: 43, new: 32)
      ]
    end

    # A day with `dau` builders, `new` of them new, the rest current. A third of each state keeps building.
    def steady(dau:, new:)
      current = dau - new
      Growth::Day.new(
        date: Date.new(2026, 10, 27), counts: { "new" => new, "current" => current },
        transitions: {
          "new" => { "current" => (new / 3.0).ceil, "at_risk" => new - (new / 3.0).ceil },
          "current" => { "current" => (current / 3.0).ceil, "at_risk" => current - (current / 3.0).ceil }
        }.reject { |_, moves| moves.values.sum.zero? }
      )
    end

    def day
      Growth::Day.new(
        date: Date.new(2026, 10, 27),
        counts: { "new" => 10, "current" => 100, "at_risk" => 50, "lapsed" => 200 },
        transitions: {
          "new" => { "current" => 4, "at_risk" => 6 },
          "current" => { "current" => 80, "at_risk" => 20 },
          "at_risk" => { "returning" => 5, "at_risk" => 35, "lapsed" => 10 },
          "lapsed" => { "lapsed" => 200 }
        }
      )
    end
end
