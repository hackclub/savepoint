require "test_helper"

class PrizeTest < ActiveSupport::TestCase
  test "every prize has a picture, and keys are unique" do
    Prize::ALL.each { |prize| assert Rails.root.join("app/assets/images/save_point/prizes", prize.image).exist?, prize.key }
    assert_equal Prize::ALL.size, Prize::ALL.map(&:key).uniq.size
  end

  test "the Roblox gift cards are in the shop, priced like the Steam cards at the same cost" do
    %w[roblox25 roblox50 roblox75 roblox100].each { |key| assert Prize.find(key), key }
    assert_equal Prize.find("steam25").hours, Prize.find("roblox25").hours
    assert_equal Prize.find("steam100").hours, Prize.find("roblox100").hours
    assert_operator Prize.find("roblox50").hours, :<, Prize.find("roblox75").hours
    assert_equal [ 25, 50, 75, 100 ], %w[roblox25 roblox50 roblox75 roblox100].map { |key| Prize.find(key).cost }
  end

  test "the PlayStation and Xbox cards cost 17 hours, like the other $100 cards, and carry terms (D-061)" do
    %w[ps100 xbox100].each do |key|
      prize = Prize.find(key)
      assert prize, key
      assert_equal 100, prize.cost
      assert_equal 17, prize.hours
      assert_equal Prize.find("steam100").hours, prize.hours
      assert prize.terms.any?, key
      assert prize.terms.frozen?
    end
    assert_match(/PlayStation Store/, Prize.find("ps100").terms.first)
    assert_match(/Microsoft Store/, Prize.find("xbox100").terms.first)
  end

  test "terms are optional: most prizes have none" do
    assert_equal [], Prize.find("micro").terms
    assert_equal %w[ps100 xbox100], Prize::ALL.select { |prize| prize.terms.any? }.map(&:key).sort
  end

  test "the cheapest prize costs $4 an hour, and a $100 prize $6" do
    cheapest = Prize::ALL.map(&:cost).min
    assert_equal 4, Prize.rate(cheapest, cheapest:)
    assert_equal 6, Prize.rate(100, cheapest:)
    assert_equal 5, Prize.rate((cheapest + 100) / 2.0, cheapest:)
    assert_equal 5, Prize.hours_for(cheapest, cheapest:), "$19.99 at $4 is 5 hours"
    assert_equal 17, Prize.find("steam100").hours, "$100 at $6 is 16.67 hours, up to the half hour"
  end

  test "hours are the cost over the rate, up to the half hour" do
    Prize::ALL.each do |prize|
      exact = prize.cost.to_s.to_r / Prize.rate(prize.cost, cheapest: Prize::CHEAPEST)
      assert_operator prize.hours, :>=, exact, prize.key
      assert_operator prize.hours - 0.5, :<, exact, prize.key
      assert_equal prize.hours * 2, (prize.hours * 2).round, prize.key
    end
  end

  test "hours never fall as cost rises, and the list runs fewest hours first" do
    by_cost = Prize::ALL.sort_by(&:cost)
    by_cost.each_cons(2) { |a, b| assert_operator a.hours, :<=, b.hours, "#{a.key} then #{b.key}" }
    assert_equal Prize::ALL.sort_by { |prize| [ prize.hours, prize.cost ] }, Prize::ALL
  end

  test "the pace spreads a prize's hours over the days left, rounded up to 5 minutes" do
    before_start = Program::STARTS_AT - 3.days
    assert_equal 7.5, Prize.find("u2c").hours
    assert_equal 45, Prize.find("u2c").pace_minutes(from: before_start) # 7.5 hours over all 10 days
    assert_equal 105, Prize.find("steam100").pace_minutes(from: before_start) # 17 hours: 102 minutes, up to 105

    assert_equal 90, Prize.find("u2c").pace_minutes(from: Program::ENDS_AT - 5.days)
    assert_equal 450, Prize.find("u2c").pace_minutes(from: Program::ENDS_AT - 1.hour), "never under a day left"
  end

  test "every prize links to its maker's page over https" do
    Prize::ALL.each do |prize|
      assert_match(%r{\Ahttps://[a-z0-9.-]+/}, prize.url, prize.key)
      assert_not_empty prize.url_host
    end
  end
end
