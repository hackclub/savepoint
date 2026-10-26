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
    simulator = Growth::Simulator.new([ balanced ] * 2, horizon: 10)
    curr = simulator.levers.find { |lever| lever.rate == "curr" }

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

  private
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
