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

  test "who's building each day, with the rest of Save Point projected either way new builders come" do
    4.times do |index|
      user = User.create!(hca_id: "ident!daily#{index}", first_name: "Daily#{index}")
      (0..index).each { |ago| user.streak_activities.create!(activity_date: Program::DATES.begin + 3 - ago, coded_seconds: 6 * 60) }
    end

    travel_to Program::DATES.begin + 4 do
      get stats_path

      assert_select ".stats__tile", text: /Built yesterday.*4/m
      assert_select ".stats__legend li", text: "Current"
      assert_select ".stats__legend li", text: "New"
      assert_select ".stats__legend li", { text: "Resurrected", count: 0 }, "nobody's been away a month"
      assert_select ".stats__lines", 3
      assert_select ".stats__toggle-option--active", "Word of mouth"
      assert_select ".stats__levers tbody tr", minimum: 1

      get stats_path(signups: "flat")
      assert_select ".stats__toggle-option--active", "Flat"
    end
  end
end
