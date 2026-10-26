require "test_helper"

class ShopHelperTest < ActionView::TestCase
  include ProjectsHelper

  test "the shelf is every prize, fewest hours first, with a project's goal marked and no state without one" do
    shelf = shop_shelf(nil)
    assert_equal Prize::ALL, shelf.map { |card| card[:prize] }
    assert_equal [ "public" ], shelf.map { |card| card[:state] }.uniq
    assert_equal [ false ], shelf.map { |card| card[:goal] }.uniq

    project = projects(:orpheus)
    project.update!(prize_key: "u2c")
    shelf = shop_shelf(project)
    assert_equal [ "u2c" ], shelf.select { |card| card[:goal] }.map { |card| card[:prize].key }
    assert_equal [ "locked" ], shelf.map { |card| card[:state] }.uniq
    assert_equal Prize.find("aseprite").hours, shelf.first[:needed]
  end

  test "hours read as 12 hrs, and a card says how many more it needs" do
    assert_equal "12 hrs", shop_hours(12)
    assert_equal "3.5 hrs", shop_hours(3.5)
    assert_equal "1 more hr needed", shop_card_status(state: "locked", needed: 1)
    assert_equal "2.5 more hrs needed", shop_card_status(state: "locked", needed: 2.5)
  end

  test "the sticker claim card is for eligible, unbanned accounts that earned them" do
    user = users(:orpheus)
    project = projects(:orpheus)
    user.rewards.create!(key: "stickers")
    assert shop_sticker_claim?(project, user)

    user.update_columns(ysws_eligible: false)
    assert_not shop_sticker_claim?(project, user.reload)

    user.update_columns(ysws_eligible: true, hackatime_trust_level: "red")
    assert_not shop_sticker_claim?(project, user.reload)
  end
end
