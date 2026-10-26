require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  test "opening the sheet records step 1, and never lowers a later step" do
    sign_in_as_orpheus
    user = users(:orpheus)
    user.update_columns(onboarding_step_reached: nil, onboarding_step_at: nil)

    get onboarding_path
    assert_response :success
    assert_equal 1, user.reload.onboarding_step_reached
    assert_not_nil user.onboarding_step_at

    user.update_columns(onboarding_step_reached: 3)
    get onboarding_path
    assert_equal 3, user.reload.onboarding_step_reached
  end

  test "the sheet shows progress with signing in done, from the furthest step reached" do
    sign_in_as_orpheus
    users(:orpheus).update_columns(onboarding_step_reached: nil)

    get onboarding_path
    assert_select ".onboarding-progress [data-onboarding-target=progressCount]", text: "1 of 5 done"
    assert_select ".onboarding-progress__seg[data-done]", count: 1
    assert_select ".onboarding-progress__next", text: "Next: Game"

    users(:orpheus).update_columns(onboarding_step_reached: 3)
    get onboarding_path
    assert_select "[data-onboarding-target=progressCount]", text: "3 of 5 done"
    assert_select ".onboarding-progress__next", text: "Next: Prize"
  end

  test "the sticker promise shows only to someone who can still earn the stickers" do
    sign_in_as_orpheus
    user = users(:orpheus)
    user.update_columns(created_at: Time.current, ysws_eligible: true, hackatime_trust_level: "green")

    get onboarding_path
    assert_select ".onboarding-progress__reward", count: 1

    user.update_columns(ysws_eligible: false)
    get onboarding_path
    assert_select ".onboarding-progress__reward", count: 0

    user.update_columns(ysws_eligible: true, created_at: 2.hours.ago)
    get onboarding_path
    assert_select ".onboarding-progress__reward", count: 0, message: "past the first hour"
  end

  test "signed out sees no progress strip" do
    get onboarding_path
    assert_response :success
    assert_select ".onboarding-progress", count: 0
  end

  test "progress needs you signed in" do
    post onboarding_progress_path, params: { step: 2 }

    assert_response :unauthorized
  end

  test "progress records the step and only moves forward" do
    sign_in_as_orpheus
    user = users(:orpheus)
    user.update_columns(onboarding_step_reached: nil, onboarding_step_at: nil)

    post onboarding_progress_path, params: { step: 3 }
    assert_response :no_content
    assert_equal 3, user.reload.onboarding_step_reached
    first_at = user.onboarding_step_at
    assert_not_nil first_at

    travel 1.minute do
      post onboarding_progress_path, params: { step: 2 }
      assert_response :no_content
      assert_equal 3, user.reload.onboarding_step_reached
      assert_equal first_at, user.onboarding_step_at, "a step back writes nothing"

      post onboarding_progress_path, params: { step: 5 }
      assert_equal 5, user.reload.onboarding_step_reached
      assert_operator user.onboarding_step_at, :>, first_at
    end
  end

  test "progress ignores junk without an error" do
    sign_in_as_orpheus
    user = users(:orpheus)
    user.update_columns(onboarding_step_reached: nil, onboarding_step_at: nil)

    [ "0", "6", "-1", "abc", "2.5", "", "99999999999999999999" ].each do |junk|
      post onboarding_progress_path, params: { step: junk }
      assert_response :no_content, "step #{junk.inspect}"
    end
    post onboarding_progress_path
    assert_response :no_content
    post onboarding_progress_path, params: { step: [ "1" ] }
    assert_response :no_content
    assert_nil user.reload.onboarding_step_reached
  end

  # D-064: step 2's rows, again, for the code link typed in step 1. A project Hackatime links to a different repo goes
  # last, with a warning.
  test "the rows put a project Hackatime links to another repo last, with a warning" do
    plain = row_names(hackatime_rows("", {}))
    first = plain.first
    rows = hackatime_rows("github.com/orpheus/rhythm-game", { first => "https://github.com/orpheus/other-game" })

    assert_response :success
    assert_equal plain.drop(1) + [ first ], row_names(rows)
    assert_equal [ first ], rows.select { |row| row.text.include?("Hackatime links this to a different repo") }.map { |row| row.at_css(".hkp__name").text }
    assert_equal rows.size, rows.count { |row| row.at_css("input[type=radio]") }, "every row can still be picked"
  end

  test "a matching repo, a blank one, or no link on Hackatime changes nothing" do
    plain = row_names(hackatime_rows("", {}))
    name = plain.first
    [
      [ "http://www.GitHub.com/Orpheus/Rhythm-Game.git/", { name => "https://github.com/orpheus/rhythm-game" } ],
      [ "", { name => "https://github.com/orpheus/other-game" } ],
      [ "github.com/orpheus/rhythm-game", {} ]
    ].each do |repo, links|
      rows = hackatime_rows(repo, links)
      assert_equal plain, row_names(rows), repo.inspect
      assert_no_match "different repo", response.body
    end
  end

  test "Hackatime is not asked for repo links when no repo was typed" do
    asked = Class.new(Hash) { def fetch(*) = raise("asked Hackatime for repo links") }.new
    before = Hackatime.stubbed_repo_urls
    Hackatime.stubbed_repo_urls = asked
    sign_in_as_orpheus
    link_hackatime(users(:orpheus))
    [ "", "   " ].each do |repo|
      get onboarding_hackatime_path, params: { repo: }
      assert_response :success
      assert_no_match "different repo", response.body
    end
    get onboarding_hackatime_path
    assert_response :success
  ensure
    Hackatime.stubbed_repo_urls = before
  end

  test "the rows still all show, with no warning, when repo links can't be read" do
    plain = row_names(hackatime_rows("", {}))
    rows = hackatime_rows("github.com/orpheus/rhythm-game", :unavailable)
    assert_response :success
    assert_equal plain, row_names(rows)
    assert_no_match "different repo", response.body
  end

  test "the rows need you signed in, and are nothing when Hackatime isn't linked" do
    get onboarding_hackatime_path, params: { repo: "github.com/a/b" }
    assert_response :unauthorized

    sign_in_as_orpheus
    get onboarding_hackatime_path, params: { repo: "github.com/a/b" }
    assert_response :no_content
  end

  private
    def hackatime_rows(repo, links)
      before = Hackatime.stubbed_repo_urls
      Hackatime.stubbed_repo_urls = { "1001" => links }
      sign_in_as_orpheus
      link_hackatime(users(:orpheus))
      get onboarding_hackatime_path, params: { repo: }
      Nokogiri::HTML.fragment(response.body).css(".hkp__row")
    ensure
      Hackatime.stubbed_repo_urls = before
    end

    def row_names(rows) = rows.map { |row| row.at_css(".hkp__name").text }

    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end
end
