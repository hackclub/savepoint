require "test_helper"

class StreaksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
  end

  teardown { Hackatime.stubbed_spans = {} }

  test "Refresh on the streak card syncs your streak now" do
    sign_in_as_orpheus
    travel_to Time.utc(2026, 10, 29, 12) do
      at = Time.utc(2026, 10, 28, 15)
      Hackatime.stubbed_spans = { "1001" => [ { "start_time" => at.to_f, "end_time" => (at + 30.minutes).to_f, "duration" => 1800 } ] }

      patch project_streak_path

      assert_redirected_to project_path
      assert_equal 1, @user.reload.current_streak
      follow_redirect!
      assert_select ".project__streak-number", "1"
      assert_select ".project__streak-checked", /Checked just now/
    end
  end

  test "when Hackatime can't be reached, it says so on the streak card" do
    sign_in_as_orpheus

    heartbeat_spans = Hackatime.method(:heartbeat_spans)
    begin
      Hackatime.define_singleton_method(:heartbeat_spans) { |*, **| raise Hackatime::Unavailable }
      patch project_streak_path
    ensure
      Hackatime.define_singleton_method(:heartbeat_spans, heartbeat_spans)
    end

    assert_redirected_to project_path
    follow_redirect!
    assert_select ".project__streak [role=alert]", /Couldn't reach Hackatime/
  end

  private
    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end
end
