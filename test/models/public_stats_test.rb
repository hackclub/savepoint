require "test_helper"

class PublicStatsTest < ActiveSupport::TestCase
  # More builders.
  def add_builders(count = 3, hours: 2)
    count.times.map do |index|
      user = User.create!(hca_id: "ident!builder#{index}", first_name: "Builder#{index}", current_streak: index + 1,
                          hackatime_uid: "90#{index}", hackatime_access_token: "token")
      user.create_project!(idea: "a game", prize_key: "micro", pace_minutes: 45,
                           build_time: "evening", signed_on: Program::DATES.begin, hackatime_projects: [ "game" ])
      user.streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: hours * 3600)
      user
    end
  end

  test "exact numbers, even small ones" do
    travel_to Program::DATES.begin + 1 do
      stats = PublicStats.new.to_h

      assert_equal 2, stats[:totals][:builders], "the two projects in the fixtures"
      assert_equal 0.0, stats[:totals][:hours]
      assert_equal [ 2, 2 ], stats[:funnel].first(2).map { |step| step[:count] }
      assert_equal 1.0, stats[:funnel].first[:share]
      assert_nil stats[:streaks][:longest], "nobody's on a streak"
    end
  end

  test "the totals, the funnel, the days and the streaks" do
    add_builders(3, hours: 6)

    travel_to Program::DATES.begin + 1 do
      stats = PublicStats.new.to_h

      assert_equal 5, stats[:totals][:builders]
      assert_equal 18.0, stats[:totals][:hours]
      assert_equal 0.0, stats[:totals][:shipped_hours]
      assert_equal [ 5, 5, 3, 3, 3, 3, 0, 0 ], stats[:funnel].map { |step| step[:count] }
      assert_in_delta 0.6, stats[:funnel][2][:share]

      first_day = stats[:daily].first
      assert_equal [ 18.0, 3 ], first_day.values_at(:hours, :builders)
      assert stats[:daily].last[:future]

      assert_equal [ 3, 3 ], stats[:streaks].values_at(:on_streak, :longest)
    end
  end

  test "hours shipped are the hours on each shipped project's newest ship, as they were when it shipped" do
    ship = ->(project, hours) do
      project.ships.create!(title: "A game", description: "A game that's at least forty characters of description long.",
                            repo_url: "https://example.com/repo", demo_url: "https://example.com/demo", hours:,
                            screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
    ship.(projects(:orpheus), 4.5).update!(status: "changes_needed")
    ship.(projects(:orpheus), 6)
    ship.(projects(:ana), 2.25)

    stats = PublicStats.new.to_h
    assert_equal 2, stats[:totals][:shipped]
    assert_equal 8.3, stats[:totals][:shipped_hours]
  end
end
