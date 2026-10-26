require "test_helper"

class BuddyPomodorosControllerTest < ActionDispatch::IntegrationTest
  setup do
    projects(:orpheus).pair_with(projects(:ana))
  end

  test "starting one, your buddy sees it and joins, and you both end at the same time" do
    sign_in(:orpheus)
    post buddy_pomodoro_path, params: { minutes: 25 }, as: :json
    assert_response :created
    started = response.parsed_body
    assert_equal [ true, true, false, "pixelana", 25 ], started.values_at("live", "you_in", "buddy_in", "buddy", "minutes")

    users(:ana).update!(hackatime_uid: "1003", hackatime_access_token: "token-ana")
    projects(:ana).update!(hackatime_projects: [ "pong" ], repo_later: true, buddy_skipped: true)
    sign_in(:ana)
    get buddy_pomodoro_path, as: :json
    assert_equal [ true, false ], response.parsed_body.values_at("live", "you_in")
    get project_path
    assert_select ".project__buddy-live:not([hidden])", /orph started a 25-min pomodoro/

    post join_buddy_pomodoro_path, as: :json
    joined = response.parsed_body
    assert_equal [ true, true ], joined.values_at("you_in", "buddy_in")
    assert_equal started["ends_at"], joined["ends_at"]
    assert projects(:ana).pair.pomodoro_together?, "your first pomodoro together lists you as a pair"

    sign_in(:orpheus)
    get buddy_pomodoro_path, as: :json
    assert response.parsed_body["buddy_in"]
  end

  test "starting one while one's going joins that one instead" do
    sign_in(:ana)
    post buddy_pomodoro_path, params: { minutes: 45 }, as: :json
    sign_in(:orpheus)
    post buddy_pomodoro_path, params: { minutes: 15 }, as: :json

    assert_equal 1, BuddyPomodoro.count
    assert_equal 45, response.parsed_body["minutes"]
  end

  test "once it's over there's nothing to join, and without a buddy there's nothing at all" do
    sign_in(:orpheus)
    post buddy_pomodoro_path, params: { minutes: 15 }, as: :json
    travel 16.minutes do
      get buddy_pomodoro_path, as: :json
      assert_equal false, response.parsed_body["live"]
      post join_buddy_pomodoro_path, as: :json
      assert_response :not_found
    end

    Pair.destroy_all
    get buddy_pomodoro_path, as: :json
    assert_response :not_found
  end

  private
    def sign_in(name)
      user = users(name)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, first_name: user.first_name, name: user.name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
