require "application_system_test_case"
require_relative "../support/admin_mcp_helpers"

# D-063: the review page's keys, its deflate presets, and the claim banner, in a real browser.
class AdminReviewTest < ApplicationSystemTestCase
  include AdminMcpHelpers

  setup do
    create_insights_views
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    travel_to(Program::STARTS_AT + 2.days) do
      users(:ana).streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 7.5 * 3600)
      @ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.", changes_made: "Added a second ball.",
                                           repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", hackatime_projects: [ "pong" ], hours: 7.5,
                                           screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
    # 7.5 counted, 1.5 of it AI coding and 2 art: coding 5.5, capped at 4.5, and art at most 1.92.
    @ship.update_columns(ai_coding_seconds: 90 * 60, art_seconds: 2 * 3600)
    sign_in
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "a coding preset fills the field with a share of the claimed coding, and the art limit and total follow" do
    visit admin_ship_path(@ship)
    assert_selector "[data-deflate-target=total]", text: "6.42"

    find("button[data-action='deflate#setCoding'][data-percent='50']").click
    assert_equal "2.75", find("input[name=coding_hours]").value
    assert_equal "1.18", find("input[name=art_hours]").value, "art is held at 30% of the new total"
    assert_selector "[data-deflate-target=total]", text: "3.93"
    assert_no_selector "[data-deflate-target=hold][hidden]", visible: :all

    find("button[data-action='deflate#setArt'][data-percent='50']").click
    assert_equal "1", find("input[name=art_hours]").value
    assert_selector "[data-deflate-target=total]", text: "3.75"

    find("button[data-action='deflate#setCoding'][data-percent='75']").click
    assert_equal "4.13", find("input[name=coding_hours]").value, "75% of 5.5, under the 4.5 cap"
    find("button[data-action='deflate#setCoding'][data-percent='15']").click
    assert_equal "0.83", find("input[name=coding_hours]").value
  end

  test "raising the AI coding hours lowers the coding maximum on the page (D-102)" do
    visit admin_ship_path(@ship)
    assert_equal "4.5", find("input[name=coding_hours]").value, "coding 5.5 less two thirds of Hackatime's 1.5"
    fill_in "AI coding hours", with: "3"
    fill_in "Why (what looked AI-generated)", with: "One pasted dump holds the game"
    click_on "Set AI coding"
    assert_selector "#admin-ship-ai-coding", text: "Hackatime 1.5 hrs, raised to 3 hrs"
    assert_equal "3.5", find("input[name=coding_hours]").value, "coding 5.5 less two thirds of 3 is 3.5"
  end

  test "on a later ship the presets and the total work on the new hours, with the earlier approval added back (D-097)" do
    travel_to(Program::STARTS_AT + 1.5.days) do
      earlier = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.", changes_made: "First.",
                                             repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", hackatime_projects: [ "pong" ], hours: 3,
                                             screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
      earlier.update_columns(status: "approved", approved_hours: 3, review_hours: 3, review_coding_hours: 3, review_art_hours: 0,
                             decided_by_id: users(:ana).id, decided_at: Time.current)
    end
    visit admin_ship_path(@ship)
    assert_selector "#admin-ship-already-approved", text: "Already approved: 3 hrs"
    assert_selector "[data-deflate-target=total]", text: "6.42"

    find("button[data-action='deflate#setCoding'][data-percent='50']").click
    assert_equal "1.25", find("input[name=coding_hours]").value, "half of the 2.5 new coding hours claimed"
    assert_equal "1.82", find("input[name=art_hours]").value, "art held at 30% of the 4.25 coding approved so far"
    assert_selector "[data-deflate-target=total]", text: "6.07"
  end

  test "keys focus the fields, and a verdict key needs pressing twice" do
    visit admin_ship_path(@ship)
    body = find("body")

    body.send_keys("h")
    assert_equal "coding_hours", evaluate_script("document.activeElement.name")
    find("input[name=coding_hours]").send_keys(:escape)
    evaluate_script("document.activeElement.blur()")
    body.send_keys("j")
    assert_equal "review_judgement", evaluate_script("document.activeElement.name")
    evaluate_script("document.activeElement.blur()")
    body.send_keys("f")
    assert_equal "review_feedback", evaluate_script("document.activeElement.name")
    evaluate_script("document.activeElement.blur()")

    body.send_keys("c")
    assert_selector "button[name=decision][value=changes_needed].is-armed"
    assert @ship.reload.in_review?, "once arms it"
    body.send_keys("c")
    assert_text "Tell the participant what to change"
    assert @ship.reload.in_review?, "twice sends the form, which wants a note"

    fill_in "review_feedback", with: "Add a README."
    evaluate_script("document.activeElement.blur()")
    find("body").send_keys("c", "c")
    assert_text "Changes needed"
    assert @ship.reload.changes_needed?
    assert_equal "Add a README.", @ship.review_feedback
  end

  test "another admin's open ship shows who holds it, with a way to take over" do
    other = User.create!(hca_id: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi", slack_id: "U0HEIDI")
    Claim.acquire(@ship, "review", other)
    visit admin_ship_path(@ship)
    assert_selector "#admin-ship-claim", text: "Heidi is working on this review"
    click_on "Take over"
    assert_no_selector "#admin-ship-claim:not([hidden])"
    assert_equal users(:orpheus), Claim.find_by!(ship: @ship, stage: "review").user
  end

  private
    def sign_in
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
      visit root_path
      execute_script(<<~JS)
        const form = document.createElement("form")
        form.method = "post"
        form.action = "/auth/hackclub"
        document.body.append(form)
        form.submit()
      JS
      assert_selector ".top-bar"
    end
end
