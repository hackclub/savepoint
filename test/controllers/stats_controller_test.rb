require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
  test "anyone can see Save Point in numbers, exactly, with nobody named" do
    get stats_path

    assert_response :success
    assert_select "h1", "Save Point in numbers"
    assert_select ".stats__tile", text: /Builders\s*2/
    assert_select ".stats__tile", text: /Hours shipped\s*0/
    assert_select ".stats__bars th", "Linked Hackatime"
    assert_select ".stats__column", Program::DATES.count * 2, "hours per day, and who's building per day"
    assert_select "#stats-growth h2", "Who's building each day"
    assert_no_match(/Orpheus|Ana\b|Lovelace|orph|pixelana/, response.body)
  end

  test "who's building each day, with the rest of Save Point projected flat until word of mouth has a few steady days" do
    4.times do |index|
      user = User.create!(hca_id: "ident!daily#{index}", first_name: "Daily#{index}")
      (0..index).each { |ago| user.streak_activities.create!(activity_date: Program::DATES.begin + 3 - ago, coded_seconds: 6 * 60) }
    end

    travel_to Program::DATES.begin + 4 do
      get stats_path

      assert_select ".stats__tile", text: /Built yesterday.*4/m
      assert_select ".stats__legend li", text: "Built yesterday too"
      assert_select ".stats__legend li", text: "New"
      assert_select ".stats__legend li", { text: "Back after days off", count: 0 }, "nobody's taken a day off"
      assert_select ".stats__lines", 2
      assert_no_match(/\bMAU\b|\bWAU\b|monthly|resurrect|dormant/i, response.body)
      assert_select ".stats__toggle-option", { count: 0, text: "Word of mouth" }
      assert_select ".stats__note", text: /Word of mouth needs a few days of steady building first\./

      get stats_path(signups: "word_of_mouth")
      assert_select ".stats__note", text: /Word of mouth needs a few days of steady building first\./
    end
  end

  test "word of mouth is offered, and the default, once three days had ten builders the day before" do
    40.times do |index|
      user = User.create!(hca_id: "ident!steady#{index}", first_name: "Steady#{index}")
      (index % 4..3).each { |day| user.streak_activities.create!(activity_date: Program::DATES.begin + day, coded_seconds: 6 * 60) }
    end

    travel_to Program::DATES.begin + 4 do
      get stats_path

      assert_select ".stats__toggle-option--active", "Word of mouth"
      assert_select ".stats__toggle-option", "Flat"
      assert_select ".stats__note", { text: /Word of mouth needs a few days/, count: 0 }

      get stats_path(signups: "flat")
      assert_select ".stats__toggle-option--active", "Flat"
    end
  end
end
