require "application_system_test_case"

class ProjectTest < ApplicationSystemTestCase
  setup do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    mock_hackatime
    visit onboarding_path
  end

  test "setting up: link Hackatime, then your project, put off the repo and skip a buddy, one step at a time" do
    sign_in_and_open_project

    assert_selector ".project__note", text: "Nothing's linked yet, so your hours won't count."
    assert_selector ".top-bar__avatar .avatar[aria-hidden=true][title=\"orph\"]"
    assert_text "Streaks and the leaderboard open once you're set up."
    click_on "Link Hackatime"

    assert_selector ".project__note", text: "Hackatime's linked. Which project is yours?"
    assert_selector ".project__step[data-state=done]", text: "Hackatime linked"
    assert_selector ".project__setup-count", text: "3 optional steps left"
    assert_no_button "Pick a project"
    find(".hkp__row", text: "rhythm-game").click # ticking links it

    assert_selector ".project__note", text: "Hours count now. A couple of quick things and you're in."
    assert_selector ".project__step[data-state=current]", text: "Add your git repo"
    click_on "Later"
    assert_selector ".project__step[data-state=current]", text: "Bring a buddy"
    assert_selector ".project__step[data-state=later]", text: "Git repo"
    assert_no_selector ".project__step[data-state=done]", text: "Git repo"
    assert_selector ".project__step[data-state=later] .project__step-number", text: "3"
    within(".project__step[data-state=current]") { click_on "Skip" }

    assert_selector ".project__linked .project__linked-project", text: "rhythm-game"
    assert_no_selector ".project__note"
    assert_selector ".project__setup-summary", exact_text: "Git repo put off"
    assert_selector ".project__streak-number", text: "0"
    within(".project__streak") { click_on "Refresh" }
    assert_selector ".project__streak-checked", text: "Checked just now"

    assert_selector ".side-section[open][data-section=streak]"
    wait_for_side_sections
    find(".side-section__row", text: "Play party").click
    assert_no_selector ".side-section[open][data-section=streak]"
    wait_for_side_sections
    click_on "Add my game to the queue"
    assert_selector ".project__party-queued", text: "In the queue"
    click_on "Take my game out"
    assert_no_selector ".project__party-queued"
    assert_no_button "Take my game out"
    assert_button "Add my game to the queue"
  end

  test "with nothing on Hackatime yet, the project step says how to get a first session there" do
    link_hackatime(users(:orpheus))
    before = Hackatime.stubbed_projects
    Hackatime.stubbed_projects = before.merge("1001" => [])
    sign_in_and_open_project

    assert_selector ".project__note", text: "Hackatime's linked. Start building and your project links itself once you log time."
    # It waits its turn (the repo's the step to do), but stays open with how to get that first session there.
    assert_selector ".project__step[data-state=pending]", text: "Log your first time on Hackatime"
    assert_selector ".project__step[data-state=pending] .project__step-waiting",
                    text: "Hackatime hasn't seen any coding from you yet"
    assert_selector ".project__step[data-state=current]", text: "Add your git repo"
  ensure
    Hackatime.stubbed_projects = before
  end

  test "renaming your project in place, and adding a screenshot" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project

    click_on "Rename"
    fill_in "Project name", with: "Beat Sheet\n"
    assert_selector ".project__title-button", text: "Beat Sheet"

    click_on "Rename"
    fill_in "Project name", with: "Something else"
    find_field("Project name").send_keys(:escape)
    assert_selector ".project__title-button", text: "Beat Sheet"

    find(".project__shot-slot input[type=file]", visible: :all).attach_file(file_fixture("screenshot.png"), make_visible: true)
    assert_selector ".project__shot-image[alt='Screenshot of Beat Sheet']"
  end

  test "seeing which Hackatime projects are linked, and changing them" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project
    assert_selector ".project__linked-project", text: "rhythm-game"

    within(".project__linked") { click_on "Change" }
    assert_selector ".hkp__row:has(:checked)", text: "rhythm-game"
    find(".hkp__row", text: "beat-sheet-art").click # ticking saves at once: no Save button
    assert_no_button "Save"

    assert_selector ".project__linked .project__linked-project", count: 2
    assert_equal [ "rhythm-game", "beat-sheet-art" ], all(".project__linked .project__linked-project").map(&:text)

    find(".hkp__row", text: "rhythm-game").click # unticking really unlinks it (the list is still open)
    assert_selector ".project__linked .project__linked-project", count: 1
    assert_selector ".project__linked", text: "beat-sheet-art"
  end

  test "Change opens the Hackatime tick list under Hours from, ticks save in place, and Done closes it" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project

    assert_no_selector ".project__setup-summary", text: "Changing your Hackatime projects"
    assert_selector ".project__linked-panel", visible: :hidden
    within(".project__linked") { click_on "Change" }
    assert_selector ".project__linked-panel", visible: :visible
    assert_selector ".project__linked-change", text: "Done"
    assert_selector ".hkp", count: 1
    assert_no_selector ".project__step"
    find(".hkp__row", text: "rhythm-game").click # unticks the only one: hours need a project, so nothing is sent
    assert_selector ".hkp__status", text: "Pick at least one project"
    assert_equal [ "rhythm-game" ], projects(:orpheus).reload.hackatime_projects

    execute_script("window.sameDocument = true")
    find(".hkp__row", text: "beat-sheet-art").click
    assert_selector ".project__linked-project", text: "beat-sheet-art"
    find(".hkp__row", text: "rhythm-game").click
    assert_selector ".project__linked-project", text: "rhythm-game", count: 1
    assert_selector ".project__linked-project", count: 2
    assert_selector ".project__linked-panel", visible: :visible # still open after two ticks in a row
    assert evaluate_script("window.sameDocument === true"), "saving swapped parts in place"
    assert_equal [ "beat-sheet-art", "rhythm-game" ].sort, projects(:orpheus).reload.hackatime_projects.sort

    click_on "Done"
    assert_selector ".project__linked-panel", visible: :hidden
    assert_selector ".project__linked-change", text: "Change"
    assert_selector ".project__linked-project", count: 2
  end

  test "the leaderboard ranks everyone set up, and you" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project
    open_side_section("Leaderboard")
    click_on "See all"

    assert_current_path leaderboard_path
    assert_selector "h1", text: "Leaderboard"
    assert_selector "tr[data-you]", text: "You"
    assert_no_text "Most hours built this week."
    assert_selector ".leaderboard__sort[aria-current=page]", text: "Today"
    assert_selector "th", text: /hours today/i
    click_on "Total"
    assert_selector ".leaderboard__sort[aria-current=page]", text: "Total"
    assert_selector "th", text: /total hours/i
  end

  test "shipping: the form says what it still needs, then it's in review" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project
    find(".project__ship").click

    assert_selector ".ship__heading", text: "Ship your project"
    assert_button "Ship it", disabled: true
    assert_selector ".ship__check[data-check=screenshot]:not([data-done]) .ship__fix", text: "Fix"
    assert_selector ".ship__progress", text: "2 of 13"

    fill_in "Title", with: "Beat Sheet"
    fill_in "Description", with: "A rhythm game where every beat is a cell lighting up in time."
    assert_selector ".ship__count[data-enough]"
    fill_in "What did you change since last time?", with: "Added a combo meter."
    # The live checker asks GitHub and the demo link: answer it from here, never the network.
    Web.adapter = lambda do |_method, url, _headers|
      body = if url.end_with?("/readme") then { encoding: "base64", content: Base64.encode64("Play it: https://example.com/beat") }.to_json
      elsif url.include?("/commits") then "[]"
      else { private: false }.to_json
      end
      Web::Response.new(status: 200, headers: {}, body:)
    end
    fill_in "Repo URL", with: "github.com/orpheus/beat-sheet"
    fill_in "Playable link", with: "https://example.com/beat"
    find(".ship__shot input[type=file]", visible: :all).attach_file(file_fixture("screenshot.png"), make_visible: true)
    check "It shows the game running, not a mockup."

    assert_selector ".ship__submit:not(:disabled)"
    click_on "Ship it"
    assert_selector ".ship__done-title", text: "Shipped."
    click_on "Back to project"
    assert_selector ".project__title", text: "Beat Sheet"
    assert_selector ".project__ship", text: "In review"
  ensure
    Web.adapter = nil
  end

  test "shipping: items already met aren't listed, a met one leaves after its green check, and an unmet one comes back" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project
    find(".project__ship").click

    # The title and the Hackatime project are met when the page opens, so they're not shown at all.
    assert_selector ".ship__check[data-check=description]", text: "Write a description"
    assert_no_selector ".ship__check[data-check=title]"
    assert_no_selector ".ship__check[data-check=hackatime]"
    assert_no_selector ".ship__check[data-check=descmin]" # the length item only shows once there is a short description
    assert_selector ".ship__progress", text: "2 of 13"

    fill_in "Description", with: "A rhythm game where every beat is a cell lighting up in time."
    assert_selector ".ship__check[data-check=description][data-done]", wait: 1 # its green check shows first
    assert_selector ".ship__progress", text: "4 of 13" # met: the description, and its 40 characters
    assert_no_selector ".ship__check[data-check=description]", wait: 5 # then the whole row goes
    assert_no_selector ".ship__check[data-check=descmin]"

    fill_in "Description", with: "ten chars!"
    assert_selector ".ship__check[data-check=descmin]:not([data-done])", text: "Make the description 40+ characters", wait: 1 # short again, it comes back
    assert_no_selector ".ship__check[data-check=description]", wait: 1 # it has some words, so "Write a description" stays gone
    assert_selector ".ship__progress", text: "3 of 13"

    fill_in "Description", with: ""
    assert_selector ".ship__check[data-check=description]:not([data-done])", text: "Write a description", wait: 1
    assert_no_selector ".ship__check[data-check=descmin]"
  end

  test "shipping: a check that looks at a link isn't listed until the link is filled in, and the playable link's only if it fails to load" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    Web.adapter = lambda do |_method, url, _headers|
      next Web::Response.new(status: 404, headers: {}, body: "") if url.start_with?("https://example.com/gone")

      body = if url.end_with?("/readme") then { encoding: "base64", content: Base64.encode64("https://example.com/gone") }.to_json
      elsif url.include?("/commits") then "[]"
      else { private: false }.to_json
      end
      Web::Response.new(status: 200, headers: {}, body:)
    end
    sign_in_and_open_project
    find(".project__ship").click

    assert_selector ".ship__check[data-check=repolink]", text: "Add a repository link"
    assert_selector ".ship__check[data-check=demolink]", text: "Add a playable link"
    assert_selector "label[for=ship_demo_url]", text: /playable link/i
    assert_no_text "Demo URL"
    [ "repo", "readme", "readme_demo", "demo", "commits" ].each { assert_no_selector ".ship__check[data-check=#{it}]" }

    fill_in "Repo URL", with: "github.com/orpheus/beat-sheet"
    assert_selector ".ship__progress", text: "3 of 13", wait: 5 # the repository link is in, and GitHub's answered
    assert_no_selector ".ship__check[data-check=repo]" # a check that passes is never listed
    assert_no_selector ".ship__check[data-check=readme_demo]"
    assert_no_selector ".ship__check[data-check=demo]"

    fill_in "Playable link", with: "https://example.com/gone"
    assert_selector ".ship__check[data-check=demo]", text: "Make sure your playable link loads", wait: 5 # only now, because it fails
    assert_button "Ship it", disabled: true

    fill_in "Playable link", with: "https://example.com/beat"
    assert_no_selector ".ship__check[data-check=demo]", wait: 5 # it loads, so it's never listed
  ensure
    Web.adapter = nil
  end

  test "shipping: ticking a Hackatime project saves at once and updates the page without touching what you typed" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project
    find(".project__ship").click

    fill_in "What did you change since last time?", with: "Added a combo meter."
    assert_selector ".hkp__row:has(:checked)", text: "rhythm-game"
    find(".hkp__row", text: "beat-sheet-art").click
    assert_selector ".hkp__status", text: "Saved", wait: 5
    assert_equal [ "rhythm-game", "beat-sheet-art" ], projects(:orpheus).reload.hackatime_projects
    assert_field "What did you change since last time?", with: "Added a combo meter."

    find(".hkp__row", text: "rhythm-game").click
    assert_selector ".hkp__status", text: "Saved", wait: 5
    assert_equal [ "beat-sheet-art" ], projects(:orpheus).reload.hackatime_projects

    find(".hkp__row", text: "beat-sheet-art").click # none left ticked: nothing is sent, and the checklist asks for one
    assert_selector ".hkp__status", text: "Pick at least one project"
    assert_selector ".ship__check[data-check=hackatime]:not([data-done])", text: "Link a Hackatime project", wait: 3
    assert_equal [ "beat-sheet-art" ], projects(:orpheus).reload.hackatime_projects
    assert_button "Ship it", disabled: true
  end

  test "a pomodoro: lock in for as long as you pick, pause, end it, then back to the project" do
    with_hackatime_hours(1.5) do
      link_hackatime(users(:orpheus))
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      sign_in_and_open_project
      assert_checked_field "25", visible: :all
      find(".project__length", text: "15").click
      click_on "Start pomodoro"

      assert_selector ".focus__label", text: "LOCKED IN · ROUND 1"
      assert_selector ".focus__clock", text: /\A(15:00|14:5\d)\z/
      assert_selector ".focus__title", text: "a rhythm game"
      assert_selector ".focus__tracked", text: "1.5 of 6.5 hrs"
      assert_selector ".focus__synced", text: "just now"
      assert_no_selector ".focus__note-text"
      assert_selector ".focus__track-name", text: "Morning Coffee"
      find("button[aria-label='Refresh hours from Hackatime']").click
      assert_selector ".focus__synced", text: "just now"
      click_on "Pause"
      assert_selector ".focus__label", text: "PAUSED · ROUND 1"
      click_on "Resume"
      click_on "End pomodoro"

      assert_selector ".focus__label", text: "POMODORO DONE"
      assert_selector ".focus__title", text: "Pomodoro done."
      assert_no_text "Nothing to submit"
      assert_no_selector ".focus__note-text", visible: :visible
      click_on "Take a 5 min break"
      assert_selector ".focus__label", text: "BREAK"
      assert_selector ".focus__clock", text: /\A(05:00|04:5\d)\z/
      click_on "Skip break"
      assert_selector ".focus__label", text: "LOCKED IN · ROUND 2"
      find("button[aria-label='Next track']").click
      assert_selector ".focus__track-name", text: "Glad To Be Stuck Inside"

      click_on "Exit"
      assert_no_selector ".focus"
      assert_selector ".project__title", text: "a rhythm game"

      visit project_path
      assert_checked_field "15", visible: :all # remembered
    end
  end

  test "the gold pill under the pomodoro lengths slides to the one you pick" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project
    box = "(() => { const o = document.querySelector('.project__length:has(:checked)').getBoundingClientRect(); " \
          "const p = document.querySelector('.project__length-pill').getBoundingClientRect(); " \
          "return [ Math.round(o.left - p.left), Math.round(o.top - p.top), Math.round(o.width - p.width) ] })()"
    assert_selector ".project__lengths[data-ready]" # the controller places the pill a frame after connecting
    assert_equal [ 0, 0, 0 ], evaluate_script(box)
    find(".project__length", text: "60").click
    assert_checked_field "60", visible: :all
    sleep 0.5 # the slide takes 320ms
    assert_equal [ 0, 0, 0 ], evaluate_script(box)
  end

  test "picking a pomodoro length with the page scrolled doesn't scroll it away" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_and_open_project
    page.current_window.resize_to(1280, 600)
    execute_script("document.querySelector('.project__lengths').scrollIntoView({ block: 'center' })")
    scrolled = evaluate_script("Math.round(document.scrollingElement.scrollTop)")
    assert_operator scrolled, :>, 0
    find(".project__length", text: "60").click

    assert_checked_field "60", visible: :all
    assert_equal scrolled, evaluate_script("Math.round(document.scrollingElement.scrollTop)")
  end

  test "a pomodoro with your buddy: one starts, the other joins, and you count down together" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    users(:ana).update!(hackatime_uid: "1003", hackatime_access_token: "token-ana")
    projects(:ana).update!(hackatime_projects: [ "pong" ], repo_later: true, buddy_skipped: true)
    projects(:orpheus).pair_with(projects(:ana))

    sign_in_and_open_project
    find(".project__length", text: "45").click
    click_on "With pixelana"
    assert_selector ".focus__label", text: "LOCKED IN WITH PIXELANA · ROUND 1"
    assert_selector ".focus__together", text: "waiting for pixelana"
    assert_selector ".focus__clock", text: /\A(45:00|44:5\d)\z/

    using_session(:ana) do
      mock_hack_club_auth(uid: users(:ana).hca_id, slack_id: "U0ANA", first_name: "Ana", name: "Ana Lovelace")
      visit onboarding_path
      execute_script('const f=document.createElement("form");f.method="post";f.action="/auth/hackclub";document.body.append(f);f.submit()')
      assert_current_path onboarding_path
      visit project_path
      assert_selector ".project__buddy-live", text: "orph started a 45-min pomodoro. Join in."
      click_on "Join"
      assert_selector ".focus__label", text: "LOCKED IN WITH ORPH · ROUND 1"
      assert_selector ".focus__together", text: "with orph · in"
      assert_selector ".focus__clock", text: /\A44:[0-5]\d\z/
    end
  end

  test "the avatar opens your account, where you can log out" do
    sign_in_and_open_project
    find(".top-bar__avatar").click
    click_on "Log out"

    assert_current_path root_path
    assert_selector "h1", text: "Finish that game you started"
  end

  test "once you're done with onboarding, its tab goes" do
    skip "the old program's dates: it fails once the program has passed this point (2026-11-08). Rework for Save Point."
    sign_in_and_open_project
    assert_no_selector ".sheet-tab", text: "Onboarding"
    assert_equal [ "My project", "Buddy", "Leaderboard" ], all(".sheet-tab").map(&:text)

    visit onboarding_path
    assert_selector ".sheet-tab[aria-current=page]", text: "Onboarding"
    assert_selector ".top-bar__project[aria-disabled=false]"
  end

  private
    # Opens a sidebar card and waits until its grow animation has ended. Capybara computes a click point once, so a
    # link inside a card that is still growing moves out from under the click and the click lands on nothing.
    def open_side_section(label)
      find(".side-section__row", text: label).click
      card = find(".side-section[open]:not([data-closing])", text: label)
      page.document.synchronize do
        raise Capybara::ExpectationNotMet, "#{label} card is still animating" unless card.evaluate_script("this.getAnimations({ subtree: true }).length === 0")
      end
    end

    # Signs in with Hack Club Auth (as Orpheus, whose project is in the fixtures) and opens the project.
    def sign_in_and_open_project
      execute_script(<<~JS)
        const form = document.createElement("form")
        form.method = "post"
        form.action = "/auth/hackclub"
        document.body.append(form)
        form.submit()
      JS
      assert_current_path onboarding_path
      visit project_path
      assert_selector "h1", text: "a rhythm game"
      execute_script("window.open = () => null") # the steps' own tabs aren't under test here
    end
end
