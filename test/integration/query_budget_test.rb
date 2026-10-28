require "test_helper"

# The project page and the leaderboard once issued a query per person on the board (about 1,200 for a real one). Their
# query counts must not grow with the number of people on it.
class QueryBudgetTest < ActionDispatch::IntegrationTest
  PEOPLE = 30

  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_url: "https://github.com/orpheus/rhythm", buddy_skipped: true)
    @user.update!(streak_synced_at: Time.current)
    build_board(PEOPLE)
    mock_hack_club_auth(uid: @user.hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
  end

  test "the project page's queries don't grow with the people on the leaderboard" do
    get project_path # warm up
    few = queries { get project_path }
    build_board(PEOPLE, offset: PEOPLE)
    many = queries { get project_path }

    assert_response :success
    assert_operator many.size, :<=, few.size + 5, "#{few.size} queries with #{PEOPLE} others, #{many.size} with #{PEOPLE * 2}:\n#{tally(many)}"
    assert_operator many.size, :<=, 80, tally(many)
  end

  test "the project page's other views stay bounded too" do
    [ { edit: "pace" }, { step: "hackatime_project" } ].each do |params|
      get project_path(params)
      count = queries { get project_path(params) }.size
      assert_response :success
      assert_operator count, :<=, 90, "#{params}: #{count} queries"
    end
  end

  test "the leaderboard's queries don't grow with the people on it" do
    [ "today", "total" ].each do |sort|
      get leaderboard_path(sort:)
      few = queries { get leaderboard_path(sort:, all: 1) }
      build_board(PEOPLE, offset: 1000 + (sort == "today" ? 0 : PEOPLE))
      many = queries { get leaderboard_path(sort:, all: 1) }
      assert_response :success
      assert_operator many.size, :<=, few.size + 5, "#{sort}: #{few.size} then #{many.size}:\n#{tally(many)}"
    end
  end

  private
    def queries
      found = []
      callback = ->(*, payload) { found << payload[:sql] unless payload[:name].in?(%w[SCHEMA]) || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      found
    end

    def tally(sqls)
      sqls.map { |sql| sql.gsub(/\d+|'[^']*'/, "?")[0, 110] }.tally.sort_by { |_, n| -n }.first(8).map { |sql, n| "#{n}x #{sql}" }.join("\n")
    end

    # People set up with hours today and before, some paired with a buddy who has done a pomodoro together, some with ships.
    def build_board(count, offset: 0)
      made = Array.new(count) do |i|
        n = offset + i
        user = User.create!(hca_id: "ident!load#{n}", email: "load#{n}@example.com", name: "Load #{n}", first_name: "Load", slack_id: "U0LOAD#{n}",
                            slack_display_name: "load#{n}", hackatime_uid: "9#{n}", hackatime_access_token: "token#{n}", current_streak: i % 7,
                            streak_synced_at: Time.current)
        project = user.create_project!(idea: "game #{n}", prize_key: "micro", pace_minutes: 30, build_time: "evening", signed_on: Date.current - 20,
                                       hackatime_projects: [ "game-#{n}" ], hackatime_link_confirmed: true)
        10.times { |d| user.streak_activities.create!(activity_date: Date.current - d, coded_seconds: 1800 + d * 60 + i * 30) }
        project
      end
      made.each_slice(2) do |a, b|
        next unless b
        pair = Pair.create!(first_project: a, second_project: b, started_on: Date.current)
        pair.pomodoros.create!(joined_at: Time.current, started_by: a, started_at: 1.day.ago, minutes: 25) if a.id.odd?
      end
    end
end
