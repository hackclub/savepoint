require "test_helper"

class LandingHelperTest < ActionView::TestCase
  test "prize tiers split the prizes into thirds by hours" do
    tiers = Prize::ALL.group_by { |prize| prize_tier(prize) }.transform_values { |prizes| prizes.map(&:key) }
    assert_equal %w[aseprite k617 micro roblox25 steam25 u2c], tiers["common"].sort
    assert_equal [ 6, 6, 6 ], %w[common rare epic].map { |tier| tiers[tier].size }
  end

  test "prizes with equal hours share a tier and tiers never fall as hours rise" do
    Prize::ALL.group_by(&:hours).each_value do |same|
      assert_equal 1, same.map { |prize| prize_tier(prize) }.uniq.size
    end
    order = %w[common rare epic]
    ranks = Prize::ALL.sort_by(&:hours).map { |prize| order.index(prize_tier(prize)) }
    assert_equal ranks.sort, ranks
  end

  test "the bled halftone keeps the plain dots and adds dots past the sides and the bottom" do
    plain = shop_halftone
    bled = shop_halftone_bleed(bleed: 34, bleed_bottom: 60)
    assert_equal plain, bled.first(plain.size)
    extra = bled.drop(plain.size)
    assert extra.any? { |x, _, _| x < 38 }
    assert extra.any? { |x, _, _| x > 362 }
    assert(extra.all? { |x, y, _| x < 38 || x > 362 || y > 372 })
  end
end
