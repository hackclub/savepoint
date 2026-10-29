require "application_system_test_case"
require_relative "../support/admin_mcp_helpers"

# D-063, D-106: the review page's keys, its deflate presets, the verdict that shows only its own fields, the closed sections,
# and the claim banner, in a real browser.
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
    pick "approved"
    assert_selector "[data-deflate-target=total]", text: "6.42"
    assert_no_field "Why deflated", visible: :visible

    find("button[data-action='deflate#setCoding'][data-percent='50']").click
    assert_field "Why deflated", visible: :visible
    assert_equal "2.75", find("input[name=coding_hours]").value
    assert_equal "1.17", find("input[name=art_hours]").value, "art is held at 30% of the new total, rounded down so it never passes it"
    assert_selector "[data-deflate-target=total]", text: "3.92"
    assert_no_selector "[data-deflate-target=hold][hidden]", visible: :all

    find("button[data-action='deflate#setArt'][data-percent='50']").click
    assert_equal "1", find("input[name=art_hours]").value
    assert_selector "[data-deflate-target=total]", text: "3.75"

    find("button[data-action='deflate#setCoding'][data-percent='75']").click
    assert_equal "4.13", find("input[name=coding_hours]").value, "75% of 5.5, under the 4.5 cap"
    find("button[data-action='deflate#setCoding'][data-percent='15']").click
    assert_equal "0.83", find("input[name=coding_hours]").value

    fill_in "coding_hours", with: "4.5"
    fill_in "art_hours", with: "1.92"
    assert_no_field "Why deflated", visible: :visible
  end

  # D-111: 5.3 counted hours, no AI coding and 5542 s of art. Coding 3.76 and art 1.54 add up to the 5.3 claimed, and the form sends
  # them as they stand. A hundredth under either is a deflation, and the box for its reason opens.
  test "the form's own figures add up to the hours claimed with no reason, and a hundredth below asks for one (D-111)" do
    users(:ana).streak_activities.update_all(coded_seconds: 19_080)
    @ship.update_columns(hours: 5.3, ai_coding_seconds: 0, art_seconds: 5542)
    visit admin_ship_path(@ship)
    pick "approved"
    assert_equal [ "3.76", "1.54" ], [ find("input[name=coding_hours]").value, find("input[name=art_hours]").value ]
    assert_selector "[data-deflate-target=total]", text: "5.3"
    assert_no_field "Why deflated", visible: :visible

    fill_in "coding_hours", with: "3.75"
    assert_field "Why deflated", visible: :visible
    fill_in "art_hours", with: "1.54"
    assert_equal "1.53", find("input[name=art_hours]").value, "art held at 30% of the lower coding, rounded down"
    assert_selector "[data-deflate-target=total]", text: "5.28"

    fill_in "coding_hours", with: "3.76"
    fill_in "art_hours", with: "1.53"
    assert_field "Why deflated", visible: :visible

    fill_in "art_hours", with: "1.54"
    assert_no_field "Why deflated", visible: :visible
    fill_in "Specific technical features", with: "A second ball with its own physics."
    find("#verdict-submit").click
    assert_text "Fraud check"
    @ship.reload
    assert_equal [ BigDecimal("5.3"), BigDecimal("5.3") ], [ @ship.claimed_hours, @ship.review_hours ]
    assert_nil @ship.deflation_reason
  end

  test "raising the AI coding hours lowers the coding maximum on the page (D-102)" do
    visit admin_ship_path(@ship)
    assert_no_selector "#raise-ai[open]", visible: :all
    pick "approved"
    assert_equal "4.5", find("input[name=coding_hours]").value, "coding 5.5 less two thirds of Hackatime's 1.5"
    find("#raise-ai summary").click
    assert_equal "1.5", find("#reviewer-ai input[name=reviewer_ai_coding_hours]")[:placeholder], "the placeholder is Hackatime's figure"
    fill_in "AI coding hours", with: "3"
    fill_in "Why (what looked AI-generated)", with: "One pasted dump holds the game"
    click_on "Set AI coding"
    assert_selector "#admin-ship-ai-coding", text: "Hackatime 1.5 hrs, raised to 3 hrs"
    assert_selector "#raise-ai[open]", visible: :all
    pick "approved"
    assert_equal "3.5", find("input[name=coding_hours]").value, "coding 5.5 less two thirds of 3 is 3.5"
  end

  test "on a later ship the presets and the total work on the new hours, with the earlier approval added back (D-097)" do
    make_later_ship
    visit admin_ship_path(@ship)
    pick "approved"
    assert_selector "#admin-ship-already-approved", text: "Already approved: 3 hrs"
    assert_selector "[data-deflate-target=total]", text: "6.42"

    find("button[data-action='deflate#setCoding'][data-percent='50']").click
    assert_equal "1.25", find("input[name=coding_hours]").value, "half of the 2.5 new coding hours claimed"
    assert_equal "1.82", find("input[name=art_hours]").value, "art held at 30% of the 4.25 coding approved so far"
    assert_selector "[data-deflate-target=total]", text: "6.07"
  end

  test "keys focus the fields once their verdict is picked, and a verdict key picks it, then sends it" do
    visit admin_ship_path(@ship)
    body = find("body")

    body.send_keys("j")
    assert_not_equal "review_judgement", evaluate_script("document.activeElement.name"), "no judgement field until a verdict is picked"

    body.send_keys("a")
    assert_selector "button[data-verdict=approved][aria-pressed=true]"
    assert_selector "#verdict-submit", text: /Approve\s*6\.42\s*hrs/i
    assert @ship.reload.in_review?, "the first press only picks"
    body.send_keys("h")
    assert_equal "coding_hours", evaluate_script("document.activeElement.name")
    find("input[name=coding_hours]").send_keys(:escape)
    evaluate_script("document.activeElement.blur()")
    body.send_keys("j")
    assert_equal "review_judgement", evaluate_script("document.activeElement.name")
    evaluate_script("document.activeElement.blur()")

    body.send_keys("c")
    assert_selector "button[data-verdict=changes_needed][aria-pressed=true]"
    assert_selector "#verdict-submit", text: "Send changes needed"
    body.send_keys("f")
    assert_equal "review_feedback", evaluate_script("document.activeElement.name")
    evaluate_script("document.activeElement.blur()")
    assert @ship.reload.in_review?, "picking sends nothing"

    body.send_keys("c")
    assert_text "Tell the participant what to change"
    assert @ship.reload.in_review?, "the second press sends the form, which wants a note"
    assert_selector "button[data-verdict=changes_needed][aria-pressed=true]"
    assert_field "Note to the participant", visible: :visible

    fill_in "review_feedback", with: "Add a README."
    evaluate_script("document.activeElement.blur()")
    find("body").send_keys("c")
    assert_text "Changes needed"
    assert @ship.reload.changes_needed?
    assert_equal "Add a README.", @ship.review_feedback
  end

  test "a verdict key pressed twice at once sends it" do
    visit admin_ship_path(@ship)
    find("body").send_keys("b", "b")
    assert_text "Write what shows the fraud"
    assert @ship.reload.in_review?, "refused without the evidence"
    assert_field "Ban evidence", visible: :visible
  end

  test "picking a verdict shows only its own fields and a submit button named for it" do
    visit admin_ship_path(@ship)
    assert_selector "button[data-verdict]", count: 4
    assert_no_selector "#verdict textarea", visible: :visible
    assert_no_selector "#verdict-submit", visible: :visible

    pick "approved"
    assert_field "Coding hours"
    assert_field "Art hours"
    assert_field "Specific technical features"
    assert_field "Your judgement"
    assert_no_field "Why deflated", visible: :visible
    assert_no_field "Note to the participant", visible: :visible
    assert_no_field "Ban evidence", visible: :visible
    assert_selector "#verdict-submit", text: /Approve\s*6\.42\s*hrs/i

    pick "changes_needed"
    assert_field "Note to the participant"
    assert_no_field "Coding hours", visible: :visible
    assert_no_field "Your judgement", visible: :visible
    assert_no_field "Ban evidence", visible: :visible
    assert_selector "#verdict-submit", text: "Send changes needed"

    pick "rejected"
    assert_field "Your judgement"
    assert_no_field "Note to the participant", visible: :visible
    assert_no_field "Coding hours", visible: :visible
    assert_selector "#verdict-submit", text: "Reject ship"

    pick "banned"
    assert_field "Ban evidence"
    assert_no_field "Your judgement", visible: :visible
    assert_selector "#verdict-submit", text: "Ban and reject"
  end

  test "approving works from the picked verdict to the fraud check" do
    visit admin_ship_path(@ship)
    pick "approved"
    fill_in "Specific technical features", with: "A second ball with its own physics."
    fill_in "Your judgement", with: "Solid."
    find("#verdict-submit").click
    assert_text "Fraud check"
    @ship.reload
    assert @ship.awaiting_fraud?
    assert_equal BigDecimal("6.42"), @ship.review_hours
    assert_equal "Solid.", @ship.review_judgement
  end

  test "changes needed is refused without the note, and goes through with it" do
    visit admin_ship_path(@ship)
    pick "changes_needed"
    click_on "Send changes needed"
    assert_text "Tell the participant what to change"
    assert @ship.reload.in_review?
    assert_field "Note to the participant", visible: :visible

    fill_in "Note to the participant", with: "Add a README."
    click_on "Send changes needed"
    assert_text "Changes needed"
    assert @ship.reload.changes_needed?
  end

  test "a later ship shows the last approved screenshot beside this one, in one panel" do
    make_later_ship
    visit admin_ship_path(@ship)
    assert_selector "#admin-ship-screenshots h2", text: "Screenshots", count: 1
    assert_selector "#admin-ship-last-approved img"
    assert_selector "#admin-ship-screenshots .ash__after img"
    assert_selector "#admin-ship-screenshots figcaption", text: /this ship/i
    left = evaluate_script("document.querySelector('#admin-ship-last-approved').getBoundingClientRect().toJSON()")
    right = evaluate_script("document.querySelector('#admin-ship-screenshots .ash__after').getBoundingClientRect().toJSON()")
    assert_operator right["left"], :>, left["right"] - 1, "side by side"
    assert_in_delta left["top"], right["top"], 2
  end

  test "the Lapse section is closed until the ship has Lapse time, then it opens with the split form" do
    visit admin_ship_path(@ship)
    assert_no_selector "details#admin-ship-lapses[open]", visible: :all
    assert_selector "details#admin-ship-lapses summary", text: /art 27% of 7.5 hrs/
    assert_no_selector "#lapse-split", visible: :visible

    @ship.update_columns(lapse_seconds: 2 * 3600)
    visit admin_ship_path(@ship)
    assert_selector "details#admin-ship-lapses[open] #lapse-split"
    assert_field "Lapse hours that were coding"
  end

  test "the closed sections and the checklist open on a click, one level deep" do
    visit admin_ship_path(@ship)
    assert_selector "#admin-ship-checklist summary", text: /Checklist\s*\d of 7/
    assert_no_selector "#admin-ship-checklist .ash__tick", visible: :visible
    find("#admin-ship-checklist summary").click
    assert_selector "#admin-ship-checklist .ash__tick", count: 7
    assert_selector "details details", count: 0, visible: :all
    assert_selector ".ash__decide #admin-ship-limits", text: /Claimed.*Counted.*AI coding.*Art.*Most to approve/m
    assert_no_selector "details#admin-ship-hours[open]", visible: :all
    find("#admin-ship-hours summary").click
    assert_selector "details#admin-ship-hours[open]"
    assert_no_text "What they submitted"
    %w[admin-ship-readme admin-ship-repo admin-ship-person admin-ship-hours-start snapshot-edit].each { |id| assert_no_selector "details##{id}[open]", visible: :all }
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
    def pick(verdict) = find("button[data-verdict=#{verdict}]").click

    # D-097, D-101: an earlier approved ship of the same project, so this one is a later ship.
    def make_later_ship
      travel_to(Program::STARTS_AT + 1.5.days) do
        earlier = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.", changes_made: "First.",
                                               repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", hackatime_projects: [ "pong" ], hours: 3,
                                               screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
        earlier.update_columns(status: "approved", approved_hours: 3, review_hours: 3, review_coding_hours: 3, review_art_hours: 0,
                               decided_by_id: users(:ana).id, decided_at: Time.current)
      end
    end

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
