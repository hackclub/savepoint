require "test_helper"

class ShipsControllerTest < ActionDispatch::IntegrationTest
  # Several tests stub the Hackatime spans (later_ship_project, and the second ship's), which every test in this process
  # shares. They go back after each test: left in place, the next page view of any test (the NPS popup's, the buddy page's)
  # would sync Orpheus's six hours from them (StreakActivity.sync_for_user!).
  setup { @spans_before = Hackatime.stubbed_spans }
  teardown { Hackatime.stubbed_spans = @spans_before }

  test "shipping opens once you're set up" do
    get project_ship_path
    assert_redirected_to onboarding_path

    sign_in_as_orpheus
    get project_ship_path
    assert_redirected_to project_path

    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    get project_ship_path
    assert_response :success
    assert_select "input#ship_title[value='a rhythm game']"
    assert_select ".hkp__input[checked][value=rhythm-game]", 1, "the linked project is ticked in the list"
    assert_select "input[type=file][name='ship[screenshot]'][accept='image/png,image/jpeg,image/webp']", 1, "no GIF: screenshots can't move"
  end

  test "a GIF screenshot is refused, with why" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus

    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params.merge(screenshot: Rack::Test::UploadedFile.new(file_fixture("animated.gif"), "image/gif")) }
    end
    assert_select ".ship__error", /Set a still screenshot as a PNG, JPEG or WebP, not a GIF/
  end

  test "shipping, then it's in review" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus

    post project_ship_path, params: { ship: ship_params }
    assert_redirected_to project_ship_path
    follow_redirect!
    assert_select ".ship__done-title", "Shipped."
    assert_select ".ship__done-text", /Beat Sheet is in review/

    assert_no_difference -> { Ship.count }, "the same screenshot can't ship twice (D-016)" do
      post project_ship_path, params: { ship: ship_params }
    end
    get project_path
    assert_select ".project__ship", /In review/
  end

  # D-109: a ship in review doesn't block the next one.

  test "shipping again replaces a ship that waits for its first review" do
    ready_to_ship
    post project_ship_path, params: { ship: ship_params }
    first = projects(:orpheus).ships.sole

    get project_path
    assert_select "a.project__ship-status", /In review/
    assert_select "a.project__ship.sp-btn--gold[href=?]", project_ship_path(again: 1), /Ship/

    get project_ship_path
    assert_select ".ship__done-title", "Shipped.", "no `again`: the confirmation of the pending ship"
    assert_select "a#ship-again[href=?]", project_ship_path(again: 1), /Ship again/
    get project_ship_path(again: 1)
    assert_select "form.ship__form"
    assert_select ".ship__replacing", /Your ship from .+ hasn't been reviewed yet. Shipping again replaces it./

    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params(title: "Beat Sheet 2", screenshot: other_screenshot) }
    end
    assert_redirected_to project_ship_path
    second = projects(:orpheus).ships.order(:id).last
    assert first.reload.superseded?
    assert_equal second, first.superseded_by
    assert second.in_review?
    follow_redirect!
    assert_select ".ship__done-text", /Beat Sheet 2 is in review/
  end

  test "shipping again leaves a ship that passed review alone and says the new one counts only the hours after it" do
    ready_to_ship
    post project_ship_path, params: { ship: ship_params }
    first = projects(:orpheus).ships.sole
    first.decide!("approved", by: users(:ana), technical_features: "A beat grid.")
    assert first.reload.awaiting_fraud?

    get project_ship_path(again: 1)
    assert_select ".ship__replacing", /passed review and is in its final check. This ship counts only the hours after it./
    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params(title: "Beat Sheet 2", screenshot: other_screenshot) }
    end
    assert first.reload.awaiting_fraud?
    assert projects(:orpheus).ships.order(:id).last.in_review?
  end

  test "a failed second ship leaves the first one in review" do
    ready_to_ship
    post project_ship_path, params: { ship: ship_params }
    first = projects(:orpheus).ships.sole
    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params(title: "Beat Sheet 2", description: "Too short", screenshot: other_screenshot) }
    end
    assert_response :unprocessable_entity
    assert first.reload.in_review?
  end

  test "while the ship waits for its fraud check the participant still sees it in review, and a final reject shows why (D-063)" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    post project_ship_path, params: { ship: ship_params }
    ship = projects(:orpheus).ships.sole

    ship.decide!("approved", by: users(:ana), technical_features: "A beat grid.")
    assert ship.reload.awaiting_fraud?
    get project_ship_path
    assert_select ".ship__done-text", /Beat Sheet is in review/
    get project_path
    assert_select ".project__ship", /In review/
    assert_no_match(/fraud/i, response.body)

    ship.send_back_to_review!(by: users(:ana), reason: "Look again.")
    ship.decide!("rejected", by: users(:ana), judgement: "A template.", feedback: "This is not your own game.")
    get project_ship_path
    assert_select ".ship__reviewer-note", "This is not your own game."
    assert_select ".ship__done-text", /can't be shipped again/
    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params }
    end
  end

  test "a participant who is due answers the NPS questions before shipping" do
    NpsResponse.asking = true
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus

    get project_ship_path
    assert_select ".ship__done[data-state=nps] .ship__done-title", "First, a few questions."
    assert_select "a[href=?]", nps_path(ship: 1)
    assert_select "form.ship__form", 0
    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params }
    end

    NpsResponse.create!(user: users(:orpheus), project: projects(:orpheus), source: "ship", score: 9, doing_well: "a", improve: "b")
    get project_ship_path
    assert_select "form.ship__form"
    get project_path
    assert_select ".project__ship", /Ship/
    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params }
    end
  end

  test "without your address, shipping waits for it: shared through Hack Club" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    users(:orpheus).update!(address: nil) # signed in before we asked

    get project_ship_path
    assert_select ".ship__done[data-state=address] .ship__done-title", "First, your address."
    assert_select "form[action=?] input[name=origin][value=?]", "/auth/hackclub?want=address", project_ship_path
    assert_select "form.ship__form", 0
    assert_select ".ship__stage", 0, "no screenshot, no empty stand"
    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params }
    end

    users(:orpheus).update!(address: HQ_ADDRESS)
    get project_ship_path
    assert_select "form.ship__form"
  end

  test "waiting on your address, the project's screenshot previews the game" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true,
                               screenshot: fixture_file_upload("screenshot.png", "image/png"))
    sign_in_as_orpheus
    users(:orpheus).update!(address: nil)

    get project_ship_path
    assert_select ".ship__done[data-state=address] .ship__stage .ship__polaroid img"
    assert_select ".ship__polaroid figcaption", projects(:orpheus).title
  end

  test "coming back from Hack Club with no address says so and offers another try" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    users(:orpheus).update!(address: nil)
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus", address: nil)

    post "/auth/hackclub?want=address", params: { origin: project_ship_path, prompt: "consent" }
    follow_redirect!
    assert_redirected_to project_ship_path
    follow_redirect!
    assert_select ".ship__address-missing", /Hack Club didn't send an address/
    assert_select "a[href^='https://auth.hackclub.com/portal/address']"
    assert_select "form[action=?] input[name=prompt][value=consent]", "/auth/hackclub?want=address"

    get project_ship_path
    assert_select ".ship__address-missing", 0, "said once"
  end

  test "viewing as someone, there's no Hack Club round trip to start" do
    admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    ana = users(:ana)
    ana.update!(address: nil, hackatime_uid: "9999", hackatime_access_token: "token-ana")
    ana.project.update!(hackatime_projects: [ "heidis-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    post admin_user_impersonation_path(ana)

    get project_ship_path
    assert_select ".ship__done[data-state=address]"
    assert_select ".ship__impersonating", /viewing as/i
    assert_select "form[action^='/auth/hackclub']", 0
  ensure
    Rails.configuration.x.admin_slack_ids = admins
  end

  test "what a ship's missing says so" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    post project_ship_path, params: { ship: ship_params.merge(description: "short", screenshot_shows_game: "0") }

    assert_response :unprocessable_entity
    assert_select ".ship__error", /Make the description 40\+ characters/
    assert_select ".ship__error", /Confirm the screenshot shows your game/
  end

  test "shipping closes after the deadline where you are, with two quiet days nobody's told about" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    users(:orpheus).update!(timezone: "America/New_York")
    sign_in_as_orpheus

    travel_to Time.utc(2026, 11, 5, 3) do # 10pm on Nov 4 in New York: still open
      get project_ship_path
      assert_select "form.ship__form"
      get project_path
      assert_select ".project__ship", /Ship/
    end

    travel_to Time.utc(2026, 11, 5, 6) do
      get project_ship_path
      assert_response :success
      assert_select ".ship__done[data-state=closed] .ship__done-title", "Shipping's closed."
      assert_select ".ship__done-text", /was Nov 2\./
      assert_select ".ship__stage", 0, "no screenshot, no empty stand"
      assert_select ".ship__done-text", { text: /Nov 4/, count: 0 }, "the grace is never mentioned"
      assert_select "form.ship__form", 0
      assert_no_difference -> { Ship.count } do
        post project_ship_path, params: { ship: ship_params }
      end
      assert_redirected_to project_ship_path
      get project_path
      assert_select ".project__ship", 0
    end
  end

  test "what changed since last time is required, and shown on the form" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    get project_ship_path
    assert_select "label[for=ship_changes_made]", "What did you change since last time?"
    assert_select "textarea#ship_changes_made[required]"
    assert_select ".ship__check[data-check=repo][data-network]"

    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params.merge(changes_made: " ") }
    end
    assert_response :unprocessable_entity
    assert_select ".ship__error", /Say what you changed since last time/

    post project_ship_path, params: { ship: ship_params }
    assert_equal "Added a combo meter.", Ship.last.changes_made
  end

  test "the live checker answers as JSON from the web, never the network in tests" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    Web.adapter = lambda do |_method, url, _headers|
      case url
      when %r{/repos/orpheus/beat-sheet/readme} then Web::Response.new(status: 404, headers: {}, body: "{}")
      when %r{/repos/orpheus/beat-sheet\z} then Web::Response.new(status: 200, headers: {}, body: { private: false }.to_json)
      else Web::Response.new(status: 404, headers: {}, body: "")
      end
    end

    get project_ship_path(format: :json, repo_url: "github.com/orpheus/beat-sheet", demo_url: "https://example.com/gone")
    assert_response :success
    items = response.parsed_body["items"].index_by { it["key"] }
    assert_equal "ok", items["repo"]["state"]
    assert_equal "fail", items["readme"]["state"]
    assert_equal "fail", items["demo"]["state"]
    assert_equal "warn", items["commits"]["state"], "a check that could not run never blocks"
    assert response.parsed_body["blocked"]
  ensure
    Web.adapter = nil
  end

  test "after changes needed the form says so and starts from what you sent" do
    link_hackatime(users(:orpheus))
    project = projects(:orpheus)
    project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    ship = project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                 repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                                 screenshot: fixture_file_upload("screenshot.png", "image/png"), screenshot_shows_game: true)
    ship.decide!("changes_needed", by: users(:ana), feedback: "Add a README that says how to run it.")
    sign_in_as_orpheus
    get project_ship_path
    assert_select ".ship__changes-needed", /Changes needed on your last ship/
    assert_select ".ship__reviewer-note", "Add a README that says how to run it."
    assert_select "input#ship_demo_url[value='https://example.com/beat']"
    assert_select "textarea#ship_description", /every beat is a cell/
  end

  test "a second ship starts from your description, with what you changed and the screenshot empty" do
    link_hackatime(users(:orpheus))
    project = projects(:orpheus)
    project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    project.screenshot.attach(fixture_file_upload("screenshot.png", "image/png"))
    ship = project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                 changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet",
                                 demo_url: "https://example.com/beat", screenshot: fixture_file_upload("screenshot.png", "image/png"),
                                 screenshot_shows_game: true)
    approve_through_fraud(ship)
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Program::STARTS_AT + 3.hours, 360) ] } # 6 new hours since that ship
    users(:orpheus).update_column(:streak_synced_at, nil)
    StreakActivity.sync_for_user!(users(:orpheus).reload)
    sign_in_as_orpheus
    get project_ship_path

    assert_select "textarea#ship_description", /every beat is a cell/
    assert_select "textarea#ship_changes_made", text: ""
    assert_select "img.ship__shot-image[hidden]:not([src])", 1, "the box starts empty, whatever the project or an earlier ship had"
    assert_select ".ship__check[data-check=screenshot] .ship__fix"
    assert_select ".ship__missing", 0
  end

  test "shipping again needs a new screenshot: the project's own and an earlier ship's don't count" do
    link_hackatime(users(:orpheus))
    project = projects(:orpheus)
    project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    project.screenshot.attach(fixture_file_upload("screenshot.png", "image/png"))
    sign_in_as_orpheus

    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params.except(:screenshot) }
    end
    assert_response :unprocessable_entity
    assert_select ".ship__error", /Set a new screenshot/

    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params }
    end
    project.ships.last.decide!("changes_needed", by: users(:ana), feedback: "Add a README.")
    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params }
    end
    assert_response :unprocessable_entity
    assert_select ".ship__error", /this one was on an earlier ship/
  end

  test "a failed submit keeps the new screenshot, and fixing the description ships with it" do
    link_hackatime(users(:orpheus))
    project = projects(:orpheus)
    project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus

    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params.merge(description: "short") }
    end
    assert_response :unprocessable_entity
    assert_select ".ship__error", /Make the description 40\+ characters/
    assert_select "img.ship__shot-image:not([hidden])[src]", 1, "the preview shows the screenshot just sent"
    assert_select "form[data-ship-carried-value=true]"
    signed_id = css_select("input[name='ship[screenshot_signed_id]']").first["value"]
    assert signed_id.present?

    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params.except(:screenshot).merge(screenshot_signed_id: signed_id) }
    end
    assert_equal "screenshot.png", Ship.last.screenshot.filename.to_s
  end

  test "shipping is blocked while the README doesn't contain the demo link (D-019)" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    readme = ->(text) { Web::Response.new(status: 200, headers: {}, body: { encoding: "base64", content: Base64.encode64(text) }.to_json) }

    Web.adapter = ->(_method, url, _headers) { url.end_with?("/readme") ? readme.("Just a game.") : Web::Response.new(status: 200, headers: {}, body: "{}") }
    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params }
    end
    assert_response :unprocessable_entity
    assert_select ".ship__error", "Put your playable link in the README"

    Web.adapter = ->(_method, url, _headers) { url.end_with?("/readme") ? readme.("Play it at http://example.com/beat/") : Web::Response.new(status: 200, headers: {}, body: "{}") }
    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params }
    end
  ensure
    Web.adapter = nil
  end

  test "the form says playable link, and lists the two link checks that always apply" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    get project_ship_path

    assert_select "label[for=ship_demo_url]", "Playable link"
    assert_select ".ship__check[data-check=repolink] .sp-item__title", "Add a repository link"
    assert_select ".ship__check[data-check=demolink] .sp-item__title", "Add a playable link"
    assert_select ".ship__check[data-check=readme_demo] .sp-item__title", "Put your playable link in the README"
    assert_select ".ship__check[data-check=demo] .sp-item__title", "Make sure your playable link loads"
    %w[repo readme readme_demo demo commits].each { assert_select ".ship__check[data-check=#{it}][data-hidden]", 1, "#{it} isn't listed until it has something to say" }
    assert_select ".ship__check[data-check=descmin][data-hidden]", 1, "the length item waits for a short description"
    assert_no_match(/demo url|demo link|your demo/i, response.body.gsub(/ship_demo_url|demo_url|readme_demo/, ""))
  end

  test "the live checker lists the README check, answered as JSON" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    Web.adapter = lambda do |_method, url, _headers|
      body = url.end_with?("/readme") ? { encoding: "base64", content: Base64.encode64("nothing here") }.to_json : (url.include?("/commits") ? "[]" : { private: false }.to_json)
      Web::Response.new(status: 200, headers: {}, body:)
    end
    get project_ship_path(format: :json), params: { repo_url: "github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat" }
    item = response.parsed_body["items"].find { it["key"] == "readme_demo" }
    assert_equal "fail", item["state"]
    assert item["blocker"]
    assert response.parsed_body["blocked"]
  ensure
    Web.adapter = nil
  end

  test "ticking and unticking Hackatime projects on the ship page links and unlinks them, as JSON" do
    link_hackatime(users(:orpheus))
    project = projects(:orpheus)
    project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    get project_ship_path
    assert_select ".hkp__row", 3
    assert_select ".hkp__input[checked]", 1

    patch hackatime_project_ship_path, params: { project: { hackatime_project_names: [ "rhythm-game", "dotfiles" ] } }, as: :json
    assert_response :success
    assert_equal [ "rhythm-game", "dotfiles" ], response.parsed_body["projects"]
    assert response.parsed_body["hours"].present?
    assert_equal [ "rhythm-game", "dotfiles" ], project.reload.hackatime_projects

    patch hackatime_project_ship_path, params: { project: { hackatime_project_names: [ "dotfiles" ] } }
    assert_equal [ "dotfiles" ], project.reload.hackatime_projects, "unticked means unlinked"

    patch hackatime_project_ship_path, params: { project: { hackatime_project_names: [ "dotfiles", "someone-elses-game" ] } }
    assert_response :unprocessable_entity
    assert_equal [ "dotfiles" ], project.reload.hackatime_projects
  end

  test "GitHub being unable to answer never stops a ship (D-022)" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 503, headers: {}, body: "{}") }

    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params }
    end
  ensure
    Web.adapter = nil
  end

  test "a carried screenshot still has to be new" do
    link_hackatime(users(:orpheus))
    project = projects(:orpheus)
    project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    post project_ship_path, params: { ship: ship_params }
    project.ships.last.decide!("changes_needed", by: users(:ana), feedback: "Add a README.")
    blob = project.ships.last.screenshot.blob

    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params.except(:screenshot).merge(screenshot_signed_id: blob.signed_id) }
    end
    assert_response :unprocessable_entity
    assert_select ".ship__error", /Set a new screenshot/
    assert_select "input[name='ship[screenshot_signed_id]']", 0, "a refused screenshot isn't carried"
  end

  test "another participant's screenshot, named by its signed id, is refused" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    projects(:ana).screenshot.attach(fixture_file_upload("screenshot.png", "image/png"))
    others = projects(:ana).screenshot.blob
    sign_in_as_orpheus

    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params.except(:screenshot).merge(screenshot_signed_id: others.signed_id) }
    end
    assert_response :unprocessable_entity
    assert_select ".ship__error", /Set a new screenshot/
    assert_equal 1, others.reload.attachments.count, "the other participant's blob is still only theirs"
  end

  test "a signed id sent as the screenshot field itself is refused" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    projects(:ana).screenshot.attach(fixture_file_upload("screenshot.png", "image/png"))
    others = projects(:ana).screenshot.blob
    sign_in_as_orpheus

    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params.merge(screenshot: others.signed_id) }
    end
    assert_response :unprocessable_entity
    assert_select ".ship__error", /Set a new screenshot/
    assert_equal 1, others.reload.attachments.count
  end

  test "a screenshot uploaded in your own session carries over to the next try, and nobody else's does" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus

    post project_ship_path, params: { ship: ship_params.merge(description: "short") }
    assert_response :unprocessable_entity
    signed_id = css_select("input[name='ship[screenshot_signed_id]']").first["value"]

    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params.except(:screenshot).merge(screenshot_signed_id: signed_id) }
    end
    assert_equal signed_id, Ship.last.screenshot.blob.signed_id
  end

  test "after an approved ship the form asks what changed since it and lists the commits since, newest first (D-100)" do
    later_ship_project
    stub_commits([ { "sha" => "abc1234567", "html_url" => "https://github.com/orpheus/beat-sheet/commit/abc", "commit" => { "message" => "Add a combo meter\n\nbody", "author" => { "name" => "Orpheus", "date" => 2.days.ago.iso8601 } } },
                   { "sha" => "def1234567", "html_url" => "https://github.com/orpheus/beat-sheet/commit/def", "commit" => { "message" => "Fix the late hit", "author" => { "name" => "Orpheus", "date" => 3.days.ago.iso8601 } } } ])
    get project_ship_path

    assert_select "label[for=ship_changes_made]", "What changed since your last ship?"
    assert_select "textarea#ship_changes_made[placeholder*='different from the version you last shipped']", text: ""
    assert_select ".ship__commits .ship__commit", 2
    assert_select ".ship__commits .ship__commit:first-child .ship__commit-message", "Add a combo meter"
    assert_select ".ship__commits-more", 0
    assert_select ".ship__check[data-check=changes] .sp-item__title", "Say what changed since your last ship"
  ensure
    Web.adapter = nil
  end

  test "more than twenty commits are cut to twenty with a count of the rest" do
    later_ship_project
    stub_commits(Array.new(25) { |n| { "sha" => "a#{n}", "html_url" => "https://x", "commit" => { "message" => "Commit #{n}", "author" => { "name" => "O", "date" => 1.day.ago.iso8601 } } } })
    get project_ship_path

    assert_select ".ship__commit", 20
    assert_select ".ship__commits-more", "+5 more"
  ensure
    Web.adapter = nil
  end

  test "when the commits can't be fetched the later form shows no list and still ships" do
    later_ship_project
    Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 503, headers: {}, body: "{}") }
    get project_ship_path

    assert_select "label[for=ship_changes_made]", "What changed since your last ship?"
    assert_select ".ship__commits", 0
    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params.merge(repo_url: "https://github.com/orpheus/beat-sheet") }
    end
  ensure
    Web.adapter = nil
  end

  test "a first ship's form is unchanged: no commit list and the old label" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    get project_ship_path

    assert_select "label[for=ship_changes_made]", "What did you change since last time?"
    assert_select ".ship__commits", 0
  end

  test "with under an hour of new time since an approved ship, the page says how much is left and create refuses (D-099)" do
    project = later_ship_project(ship_hours: -0.4)
    get project_ship_path
    assert_select ".ship__done[data-state=waiting]"
    assert_select ".ship__done-title", "Build a little more first."
    assert_select ".ship__done-text", /Ship again once you have 1 new hour since your last ship\.\s+Log 0\.6 more hrs on/
    assert_select "form.ship__form", 0

    assert_no_difference -> { Ship.count } do
      post project_ship_path, params: { ship: ship_params }
    end
    assert_redirected_to project_ship_path
    get project_path
    assert_select ".project__ship", 0, "no ship button while waiting"
    assert project.reload.ship_waiting?
  end

  test "an hour of new time opens the ship page and create works" do
    later_ship_project(ship_hours: -1)
    get project_ship_path
    assert_select "form.ship__form"
    assert_difference -> { Ship.count }, 1 do
      post project_ship_path, params: { ship: ship_params }
    end
  end

  test "changes needed on the newest ship is exempt from the minimum" do
    project = later_ship_project(ship_hours: 0)
    project.ships.new(title: "Beat Sheet 2", description: "x" * 50, repo_url: "https://github.com/orpheus/beat-sheet",
                      demo_url: "https://example.com/beat2", hours: project.hours_logged, status: "changes_needed").save!(validate: false)
    get project_ship_path
    assert_select "form.ship__form"
    assert_select ".ship__changes-needed"
    get project_path
    assert_select ".project__ship", /Ship/
  end

  test "a pending ship still shows in review, not the wait" do
    later_ship_project(ship_hours: -1)
    post project_ship_path, params: { ship: ship_params }
    get project_ship_path
    assert_select ".ship__done[data-state=shipped]"
  end

  private
    def ready_to_ship
      link_hackatime(users(:orpheus))
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      sign_in_as_orpheus
    end

    # The fixture screenshot with a trailing byte, so its checksum is new (D-016).
    def other_screenshot
      file = Tempfile.new([ "shot", ".png" ], binmode: true)
      file.write(file_fixture("screenshot.png").binread + "\n")
      file.flush
      (@tempfiles ||= []) << file
      Rack::Test::UploadedFile.new(file.path, "image/png")
    end

    # An approved earlier ship, then signed in. ship_hours: the hours that ship stored, as an offset from the hours counted now
    # (-1 leaves exactly one new hour). The default leaves two.
    def later_ship_project(ship_hours: -2)
      link_hackatime(users(:orpheus))
      project = projects(:orpheus)
      project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true, repo_url: "https://github.com/orpheus/beat-sheet")
      Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Program::STARTS_AT + 3.hours, 360) ] }
      users(:orpheus).update_column(:streak_synced_at, nil)
      StreakActivity.sync_for_user!(users(:orpheus).reload)
      project = Project.find(project.id)
      project.ships.new(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                        repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat", status: "approved",
                        hours: project.hours_logged.to_f + ship_hours, created_at: 3.days.ago).save!(validate: false)
      sign_in_as_orpheus
      Project.find(project.id)
    end

    def stub_commits(items)
      Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 200, headers: {}, body: items.to_json) }
    end

    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end

    def ship_params(overrides = {})
      { title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
        changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
        screenshot: fixture_file_upload("screenshot.png", "image/png"), screenshot_shows_game: "1" }.merge(overrides)
    end
end
