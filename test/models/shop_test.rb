require "test_helper"

class ShopTest < ActiveSupport::TestCase
  test "hours are $5 each for the first 10 and $4 after, to the cent" do
    assert_equal 0, Shop.dollars(0)
    assert_equal 32.5, Shop.dollars(6.5)
    assert_equal 50, Shop.dollars(10)
    assert_equal 54, Shop.dollars(11)
    assert_equal 90, Shop.dollars(20)
    assert_equal 50.4, Shop.dollars(10.1)
  end

  test "a price runs back into whole hours, always rounded up" do
    assert_equal 0, Shop.hours_for(0)
    assert_equal 8, Shop.hours_for(36.99)
    assert_equal 10, Shop.hours_for(50)
    assert_equal 12, Shop.hours_for(57.99)
    assert_equal 20, Shop.hours_for(90)
    assert_equal 11, Shop.hours_for(50.01)
    assert_equal 12, Shop.hours_for(50 + 4 * 2 + 0.0000001), "a hair over, from floating point, isn't an hour over"
    assert Shop.hours_for(57.99).integer?
    Prize::ALL.each do |prize|
      assert_operator Shop.dollars(Shop.hours_for(prize.cost)), :>=, prize.cost, "#{prize.key}'s hours should cover its price"
    end
  end
end
