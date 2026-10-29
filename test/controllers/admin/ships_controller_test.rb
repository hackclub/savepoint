require "test_helper"

class Admin::ShipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0ANA", "U0HEIDI" ]
    # The hours that count are the ones logged since Save Point began (D-003), so ship after the start.
    travel_to(Program::STARTS_AT + 2.days) do
      users(:ana).streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 7.5 * 3600)
      @ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                                           changes_made: "Added a second ball.", repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong",
                                           hackatime_projects: [ "pong" ], hours: 7.5, screenshot: screenshot_upload, screenshot_shows_game: true)
    end
    @heidi = User.create!(hca_id: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi", slack_id: "U0HEIDI")
  end

  teardown do
    Rails.configuration.x.admin_slack_ids = @admins
    Web.adapter = nil
    Ship::EarlierShip.token = nil
  end

  test "admins see every ship, open one in full, review it, and a pass at the fraud check approves it" do
    sign_in_as(users(:orpheus))
    get admin_ships_path

    assert_response :success
    assert_select ".pg-admin-ships__queue", /1 waiting/
    assert_select ".admin__nav a[aria-current=page]", "Ships"
    assert_select ".pg-admin-ships__note", /7\.5 hrs across every project/
    assert_select "tr##{dom_id(@ship)}", text: /Ana Lovelace.*Pong.*pong.*7\.5.*In review/m
    assert_select "tr##{dom_id(@ship)} a[href=?]", admin_ship_path(@ship), "Pong"

    get admin_ship_path(@ship)
    assert_response :success
    assert_select "h1", "Pong"
    assert_select ".leaderboard__note", /by\s+Ana Lovelace \(pixelana on Slack\)/m
    assert_select "#admin-ship-limits", text: /Claimed\s*7\.5 hrs\s*Counted.*?7\.5 hrs.*Most to approve/m
    assert_select ".ash__decide #admin-ship-limits", 1, "one hours panel, at the top of the decision"
    assert_select ".ash__main > .ash__layout > .ash__col #admin-ship-limits", 0, "not in the main column"
    assert_select "a#admin-ship-repo-link[href='https://github.com/ana/pong']"
    assert_select "a#admin-ship-demo-link[href='https://example.com/pong']"
    assert_select ".admin__ship-description", /every frame is a sprite/
    assert_select ".admin__ship-shot img[alt='Screenshot of Pong']"
    assert_select "form#verdict[action=?]", review_admin_ship_path(@ship)
    assert_select "form#verdict input[name=coding_hours][value='7.5'][max='7.5']"

    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "6", technical_features: "A second ball with its own physics.",
                                                  deflation_reason: "An hour and a half went on a menu that was cut." }
    assert_redirected_to admin_ship_path(@ship)
    @ship.reload
    assert @ship.awaiting_fraud?, "approving a review moves it to the fraud check"
    assert_equal 6, @ship.review_hours
    assert_nil @ship.approved_hours, "nothing to spend yet"
    assert_equal 0, projects(:ana).reload.hours_approved
    assert_equal users(:orpheus), @ship.reviewer
    assert_not projects(:ana).shipped?

    follow_redirect!
    assert_select ".ash__status [data-decision=awaiting_fraud]", "Fraud check"
    assert_select "form#verdict", 0
    assert_select "form#fraud-verdict[action=?]", fraud_admin_ship_path(@ship)
    assert_select "#admin-ship-review-said .ash__limits-total", /6 hrs/
    get admin_ships_path
    assert_select ".pg-admin-ships__queue", /1 waiting/, "still waiting: for its fraud check"
    assert_select "section[aria-labelledby=admin-ships-fraud] tr##{dom_id(@ship)}"
    assert_select "section[aria-labelledby=admin-ships-review] tr##{dom_id(@ship)}", 0

    sign_in_as(users(:orpheus))
    post fraud_admin_ship_path(@ship), params: { verdict: "pass" }
    assert_redirected_to admin_ship_path(@ship)
    @ship.reload
    assert @ship.approved?
    assert_equal 6, @ship.approved_hours
    assert_equal 6, projects(:ana).reload.hours_approved
    assert projects(:ana).shipped?
    assert_equal users(:orpheus), @ship.decided_by

    follow_redirect!
    assert_select ".ash__status [data-decision=approved]", "Approved"
    assert_select "form#verdict, form#fraud-verdict", 0, "decided, so no buttons"
    assert_select ".ash__status", /Approved\s*Orpheus · #{Date.current.strftime("%b %-d")}/
    assert_select "#admin-ship-fraud", /Passed by Orpheus/

    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "Add a README." }
    assert @ship.reload.approved?, "the first decision stands"
    assert_equal "That one's moved on already.", flash[:alert]

    get admin_ships_path
    assert_select ".pg-admin-ships__queue", /0 waiting/
    assert_select "tr##{dom_id(@ship)} [data-decision=approved]", /Approved.*Orpheus/m
  end

  test "the ships page has a tab for each stage, with its count, and a tab narrows the list" do
    sign_in_as(users(:orpheus))
    done = projects(:orpheus).ships.create!(@ship.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 3, screenshot: screenshot_upload,
                                                                                                                        screenshot_shows_game: true))
    done.update_columns(status: "changes_needed", decided_at: Time.current)

    get admin_ships_path
    assert_select ".pg-admin-ships__tab[aria-current=page]", /All\s*2/
    assert_select ".pg-admin-ships__tab[data-stage=in_review]", /Awaiting review\s*1/
    assert_select ".pg-admin-ships__tab[data-stage=awaiting_fraud]", /Awaiting fraud check\s*0/
    assert_select ".pg-admin-ships__tab[data-stage=changes_needed]", /Changes needed\s*1/
    assert_select "tr##{dom_id(@ship)}"
    assert_select "tr##{dom_id(done)}"

    get admin_ships_path(stage: "changes_needed")
    assert_select ".pg-admin-ships__tab[data-stage=changes_needed][aria-current=page]"
    assert_select "tr##{dom_id(done)} [data-decision=changes_needed]", /Changes needed/
    assert_select "tr##{dom_id(@ship)}", 0
    assert_select "#admin-ships-review", 0

    get admin_ships_path(stage: "in_review")
    assert_select "tr##{dom_id(@ship)}"
    assert_select "tr##{dom_id(done)}", 0
    assert_select "#admin-ships-decided", 0
  end

  test "sending a ship back lets them ship again, and the earlier one shows under the new" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "Add a README." }
    assert @ship.reload.changes_needed?
    assert_nil projects(:ana).reload.ship_in_review
    assert_not projects(:ana).shipped?

    again = projects(:ana).ships.create!(@ship.attributes.slice("title", "description", "repo_url", "demo_url", "hackatime_projects")
                                              .merge(hours: 9, screenshot: screenshot_upload, screenshot_shows_game: true))
    get admin_ship_path(again)
    assert_select "#admin-ship-others", "Earlier ships of this project"
    assert_select "tr##{dom_id(@ship)} [data-decision=changes_needed]", /Changes needed/
    assert_select "tr##{dom_id(again)}", 0

    get admin_ships_path
    assert_select ".pg-admin-ships__note", /9 hrs across every project/, "only the ship that stands counts"
  end

  test "changes needed without a note is refused, and keeps what was typed (D-049)" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: " ", review_judgement: "Thin." }
    assert_response :unprocessable_entity
    assert @ship.reload.in_review?
    assert_select ".ash__error", /Tell the participant what to change/
    assert_select "textarea[name=review_judgement]", "Thin."

    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "Add a README.", review_judgement: "Thin." }
    assert_redirected_to admin_ship_path(@ship)
    assert_equal [ "Add a README.", "Thin." ], [ @ship.reload.review_feedback, @ship.review_judgement ]

    get admin_ship_path(@ship)
    assert_select "#admin-ship-feedback", "Add a README."
    assert_select "#admin-ship-judgement", "Thin."
    assert_select ".ash__status [data-decision=changes_needed]", "Changes needed"
    assert_select ".ash__decide #admin-ship-limits", 1, "the hours panel stays once decided"
  end

  test "reject is final and needs the judgement, and the participant is told so on their ship page, not messaged" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "rejected", review_feedback: "No." }
    assert_response :unprocessable_entity
    assert_select ".ash__error", /Say what is missing: a reject is final/
    assert @ship.reload.in_review?

    post review_admin_ship_path(@ship), params: { decision: "rejected", review_judgement: "A template with a new title.", review_feedback: "This is not your game." }
    assert_redirected_to admin_ship_path(@ship)
    assert @ship.reload.rejected?
    assert_empty enqueued_jobs.select { it[:job] == SlackMessageJob }, "nobody is told (D-034)"
    get admin_ship_path(@ship)
    assert_select ".ash__status [data-decision=rejected]", "Rejected"
  end

  test "fraud at review needs the evidence, rejects the ship and bans the account" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "banned" }
    assert_response :unprocessable_entity
    assert_select ".ash__error", /Write what shows the fraud/
    assert_not users(:ana).reload.banned?

    post review_admin_ship_path(@ship), params: { decision: "banned", evidence: "Someone else's hours." }
    assert @ship.reload.rejected?
    assert users(:ana).reload.banned?
    assert_equal "Someone else's hours.", users(:ana).ban_reason
  end

  test "a deduction at the fraud check needs notes, and a ban there rejects the ship" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "approved", technical_features: "A second ball." }
    assert @ship.reload.awaiting_fraud?

    post fraud_admin_ship_path(@ship), params: { verdict: "deduct", deduct_hours: "2" }
    assert_response :unprocessable_entity
    assert_select ".ash__error", /Say why you deduct hours/
    assert @ship.reload.awaiting_fraud?

    post fraud_admin_ship_path(@ship), params: { verdict: "deduct", deduct_hours: "2", fraud_notes: "Two hours AFK." }
    assert_equal [ "approved", BigDecimal("5.5"), "deducted" ], [ @ship.reload.status, @ship.approved_hours, @ship.fraud_status ]
    get admin_ship_path(@ship)
    assert_select "#admin-ship-fraud", /Passed with a deduction by Orpheus. Two hours AFK\./
    assert_select "#admin-ship-review-hours", /Fraud deduction\s*−2/

    other = projects(:ana).ships.create!(@ship.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 3, screenshot: screenshot_upload, screenshot_shows_game: true))
    other.update_columns(status: "awaiting_fraud", fraud_status: "pending", review_hours: 3)
    post fraud_admin_ship_path(other), params: { verdict: "ban" }
    assert_response :unprocessable_entity
    post fraud_admin_ship_path(other), params: { verdict: "ban", fraud_notes: "Same repo as another account." }
    assert other.reload.rejected?
    assert users(:ana).reload.banned?
    post fraud_admin_ship_path(other), params: { verdict: "maybe" }
    assert_response :bad_request
  end

  test "a ship waiting for its fraud check goes back to review with a reason, and the form opens from the earlier review (D-063)" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "6", technical_features: "A second ball.", deflation_reason: "A menu was cut.",
                                                  review_judgement: "Solid.", review_feedback: "Nice." }
    post send_back_admin_ship_path(@ship), params: { reason: " " }
    assert_response :unprocessable_entity
    assert_select ".ash__error", /Say why it goes back to review/
    assert @ship.reload.awaiting_fraud?

    post send_back_admin_ship_path(@ship), params: { reason: "The hours look high for the changes." }
    assert_redirected_to admin_ship_path(@ship)
    assert @ship.reload.in_review?
    assert_empty enqueued_jobs.select { it[:job] == SlackMessageJob }, "nobody is told"

    get admin_ship_path(@ship)
    assert_select "[aria-labelledby=admin-ship-send-backs]", /The hours look high for the changes\./
    assert_select "[aria-labelledby=admin-ship-send-backs]", /Earlier review by Orpheus, 6 hrs approved, Solid\./
    assert_select "input[name=coding_hours][value='6.0']"
    assert_select "textarea[name=technical_features]", "A second ball."
    assert_select "textarea[name=review_judgement]", "Solid."
    assert_select "textarea[name=review_feedback]", "Nice."
    assert_select "textarea[name=deflation_reason]", "A menu was cut."
  end

  test "the verdict form has coding and art hours, presets, a live total, and the keys (D-063)" do
    @ship.update_columns(ai_coding_seconds: 90 * 60, art_seconds: 2 * 3600)
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)

    assert_select "[data-controller=shortcuts]"
    assert_select "form#verdict[data-controller~=deflate][data-controller~=verdict]"
    # 7.5 counted, 2 of it art and 1.5 AI coding: coding 5.5 claimed, 5.5 - 1 = 4.5 cap, art at most 4.5 * 30/70 = 1.92.
    assert_select "input[name=coding_hours][value='4.5'][max='4.5'][data-shortcut=h]"
    assert_select "input[name=art_hours][value='1.92'][max='2.0']"
    assert_select "[data-deflate-target=total]", "6.42"
    assert_select "button[data-action='deflate#setCoding'][data-percent]", 4
    assert_select "button[data-action='deflate#setCoding'][data-percent='15']", /15%\s*0\.83h/
    assert_select "button[data-action='deflate#setCoding'][data-percent='75']", /75%\s*4\.13h/
    assert_select "button[data-action='deflate#setArt'][data-percent]", 4
    assert_select "button[data-action='deflate#setArt'][data-percent='50']", /50%\s*1h/
    assert_select "textarea[name=review_judgement][data-shortcut=j]"
    assert_select "textarea[name=review_feedback][data-shortcut=f]"
    { "approved" => "a", "changes_needed" => "c", "rejected" => "r", "banned" => "b" }.each do |decision, key|
      assert_select "form#verdict button[type=button][data-verdict=#{decision}][data-shortcut=#{key}][data-shortcut-submit='#verdict-submit']"
    end
    assert_select "button#verdict-submit[type=submit][name=decision][hidden]", 1, "one submit button, hidden until a verdict is picked"
    assert_select "a[data-shortcut=n][href=?]", admin_review_path(skip: @ship.id)
  end

  test "the Lapse split saves, moves the limits, and refuses more than the Lapse hours (D-085)" do
    @ship.update_columns(ai_coding_seconds: 0, art_seconds: 3 * 3600, lapse_seconds: 2 * 3600)
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_select "form#lapse-split input[name=lapse_coding_hours][value='0.0'][max='2.0']"
    assert_select "#admin-ship-lapse-time", /Lapse time 2 hrs: 0 hrs coding, 2 hrs art/
    assert_select "#admin-ship-lapse-coding", 0

    patch lapse_split_admin_ship_path(@ship), params: { lapse_coding_hours: "1.5" }
    assert_redirected_to admin_ship_path(@ship)
    assert_equal BigDecimal("1.5"), @ship.reload.lapse_coding_hours
    follow_redirect!
    assert_select "#admin-ship-lapse-time", /1.5 hrs coding, 0.5 hrs art/
    assert_select "#admin-ship-lapse-coding dd", "1.5 hrs"
    assert_select "input[name=art_hours][max='1.5']" # 3 of art less 1.5 of Lapse coding

    patch lapse_split_admin_ship_path(@ship), params: { lapse_coding_hours: "2.5" }
    assert_equal BigDecimal("1.5"), @ship.reload.lapse_coding_hours
    assert_match "coding can't be more", flash[:alert]
  end

  test "the reviewer's AI coding hours save with a reason, move the limits, clear, and are refused below Hackatime's (D-102)" do
    @ship.update_columns(ai_coding_seconds: 1800, art_seconds: 0)
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_select "form#reviewer-ai input[name=reviewer_ai_coding_hours][min='0.5']"
    assert_select "form#reviewer-ai textarea[name=reviewer_ai_reason]"
    assert_select "#admin-ship-ai-coding", /\A\s*0\.5 hrs/
    assert_select "input[name=coding_hours][max='7.16']" # 7.5 less two thirds of 0.5

    patch reviewer_ai_admin_ship_path(@ship), params: { reviewer_ai_coding_hours: "3", reviewer_ai_reason: "One pasted dump" }
    assert_redirected_to admin_ship_path(@ship)
    assert_equal [ BigDecimal("3"), "One pasted dump" ], @ship.reload.values_at(:reviewer_ai_coding_hours, :reviewer_ai_reason)
    assert_equal 1, AdminAuditEvent.where(tool: "set_reviewer_ai").count
    follow_redirect!
    assert_select "#admin-ship-ai-coding", /Hackatime 0\.5 hrs, raised to 3 hrs/
    assert_select "input[name=coding_hours][max='5.5']" # 7.5 less two thirds of 3
    assert_select "form#reviewer-ai textarea", /One pasted dump/
    assert_select "button[data-verdict=approved][data-shortcut=a]"

    patch reviewer_ai_admin_ship_path(@ship), params: { reviewer_ai_coding_hours: "0.2", reviewer_ai_reason: "x" }
    assert_equal BigDecimal("3"), @ship.reload.reviewer_ai_coding_hours
    assert_match "so it can't be less", flash[:alert]
    patch reviewer_ai_admin_ship_path(@ship), params: { reviewer_ai_coding_hours: "4", reviewer_ai_reason: "" }
    assert_equal "Say what looked AI-generated", flash[:alert]

    patch reviewer_ai_admin_ship_path(@ship), params: { reviewer_ai_coding_hours: "", reviewer_ai_reason: "" }
    assert_nil @ship.reload.reviewer_ai_coding_hours
    follow_redirect!
    assert_select "input[name=coding_hours][max='7.16']"
  end

  test "the decided view and the fraud stage show the raised AI figure and its reason (D-102)" do
    @ship.update_columns(ai_coding_seconds: 1800, art_seconds: 0)
    sign_in_as(users(:orpheus))
    patch reviewer_ai_admin_ship_path(@ship), params: { reviewer_ai_coding_hours: "3", reviewer_ai_reason: "One pasted dump" }
    post review_admin_ship_path(@ship), params: { decision: "approved", technical_features: "A second ball and bounce physics." }
    assert @ship.reload.awaiting_fraud?
    get admin_ship_path(@ship)
    assert_select "#admin-ship-ai-raised", /3 hrs, above Hackatime's 0\.5 hrs\. One pasted dump/
    @ship.update_columns(status: "approved", fraud_status: "passed", decided_by_id: users(:ana).id, decided_at: Time.current, approved_hours: @ship.review_hours)
    get admin_ship_path(@ship)
    assert_select "#admin-ship-ai-raised", /One pasted dump/
  end

  test "a reviewer can't set the AI hours on their own ship" do
    sign_in_as(@ship.project.user)
    patch reviewer_ai_admin_ship_path(@ship), params: { reviewer_ai_coding_hours: "3", reviewer_ai_reason: "x" }
    assert_nil @ship.reload.reviewer_ai_coding_hours
  end

  test "a reviewer can't set the Lapse split on their own ship" do
    @ship.update_columns(art_seconds: 3600, lapse_seconds: 3600)
    sign_in_as(@ship.project.user)
    patch lapse_split_admin_ship_path(@ship), params: { lapse_coding_hours: "1" }
    assert_equal 0, @ship.reload.lapse_coding_hours
  end

  test "the fraud form has the keys" do
    @ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", review_hours: 5, review_coding_hours: 5, review_art_hours: 0)
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)

    assert_select "input[name=deduct_hours][data-shortcut=d][max='5.0']"
    { "pass" => "p", "deduct" => "x", "ban" => "b" }.each do |verdict, key|
      assert_select "button[name=verdict][value=#{verdict}][data-shortcut=#{key}][data-shortcut-confirm]"
    end
    assert_select "a[data-shortcut=n][href=?]", admin_fraud_path(skip: @ship.id)
    assert_select "details#send-back form[action=?]", send_back_admin_ship_path(@ship)
  end

  test "approving stores the judgement from the form" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "6", technical_features: "A second ball with its own physics.",
                                                  deflation_reason: "A menu was cut.", review_judgement: "Solid." }
    assert_equal "Solid.", @ship.reload.review_judgement
  end

  test "the checklist saves each tick while the ship is in review, and not after" do
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_select "[data-controller=checklist][data-checklist-url-value=?] input[type=checkbox]", checklist_admin_ship_path(@ship), 7

    patch checklist_admin_ship_path(@ship), params: { key: "runs", value: "1" }
    assert_response :no_content
    patch checklist_admin_ship_path(@ship), params: { key: "readme", value: "1" }
    patch checklist_admin_ship_path(@ship), params: { key: "runs", value: "0" }
    assert_equal({ "runs" => false, "readme" => true }, @ship.reload.review_checklist)

    get admin_ship_path(@ship)
    assert_select "input[name=readme][checked]"

    @ship.update!(approved_columns(@ship.hours, decided_at: Time.current))
    patch checklist_admin_ship_path(@ship), params: { key: "runs", value: "1" }
    assert_response :unprocessable_entity
    assert_equal false, @ship.reload.review_checklist["runs"]
    get admin_ship_path(@ship)
    assert_select "input[name=readme][checked][disabled]"
  end

  test "the checklist marks the ticks the app decided as auto, and a saved tick drops the tag (D-050)" do
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_select "input[name=screenshot][checked]"
    assert_select "label:has(input[name=screenshot]) .ash__auto[title*=attested]", "auto"
    assert_select "label:has(input[name=runs]) .ash__auto", 0

    patch checklist_admin_ship_path(@ship), params: { key: "screenshot", value: "0" }
    get admin_ship_path(@ship)
    assert_select "input[name=screenshot][checked]", 0
    assert_select "label:has(input[name=screenshot]) .ash__auto", 0
  end

  test "deciding saves the ticks the app decided under the reviewer's own (D-050)" do
    sign_in_as(users(:orpheus))
    patch checklist_admin_ship_path(@ship), params: { key: "runs", value: "1" }
    post review_admin_ship_path(@ship), params: { decision: "approved", technical_features: "A second ball." }
    assert_equal({ "runs" => true, "screenshot" => true }, @ship.reload.review_checklist)
  end

  test "the review shows what they changed beside the commits, and the game before" do
    sign_in_as(users(:orpheus))
    Ship::EarlierShip.token = "pat-test"
    begin
      Web.adapter = lambda do |_method, url, _headers|
        if url.end_with?("/readme")
          Web::Response.new(status: 200, headers: {}, body: "<p>Two paddles.</p>")
        elsif URI(url).host == "api.github.com"
          assert_includes url, "since=#{CGI.escape(Program::STARTS_AT.utc.iso8601)}" if url.include?("until=") # the commits list, not the repo facts
          Web::Response.new(status: 200, headers: {}, body: [ { sha: "abcdef123456", html_url: "https://github.com/ana/pong/commit/abcdef1",
            commit: { message: "Add second ball\n\nbody", author: { name: "Ana", date: "2026-11-12T10:00:00Z" } } } ].to_json)
        else
          assert_includes url, "app3A5kJwYqxMLOgh"
          Web::Response.new(status: 200, headers: {}, body: { records: [ { fields: { "Code URL" => "https://github.com/ana/pong/",
            "YSWS–Name" => [ "jame gam" ], "Approved At" => "2026-11-06", "Override Hours Spent" => 4,
            "Screenshot" => [ { url: "https://dl.airtable.com/before.png" } ] } } ] }.to_json)
        end
      end
      get admin_ship_path(@ship)
    end
    assert_response :success
    assert_select ".ash__statement-text", "Added a second ball."
    assert_select ".ash__commit", /abcdef1.*Add second ball.*Ana/m
    assert_select ".ash__before[data-unified=found] img[src='https://dl.airtable.com/before.png']"
    assert_select ".ash__before figcaption", /jame gam, approved 2026-11-06, 4 hrs/
    assert_select ".ash__after img[alt='Screenshot of Pong']"
    assert_select "#admin-ship-limits", text: /Counted/
    assert_select "button", /Changes needed/
    assert_select "textarea[name=review_judgement]"
  end

  test "the review says so plainly when GitHub or the Unified YSWS DB can't help" do
    sign_in_as(users(:orpheus))
    Web.adapter = ->(*) { Web::Response.new(status: 403, headers: { "x-ratelimit-reset" => "1792000000" }, body: "{}") }
    get admin_ship_path(@ship)
    assert_response :success
    assert_select "[data-commits=rate_limited]", /rate limit/
    assert_select ".ash__before[data-unified=not_configured]", /Unified YSWS DB not configured/
  end

  test "nobody else can see them, or decide" do
    get admin_ships_path
    assert_response :not_found
    get admin_ship_path(@ship)
    assert_response :not_found
    post review_admin_ship_path(@ship), params: { decision: "approved" }
    assert_response :not_found
    get admin_review_path
    assert_response :not_found
    post admin_claims_heartbeat_path, params: { id: @ship.id, stage: "review" }
    assert_response :not_found

    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    sign_in_as(@heidi)
    get admin_ships_path
    assert_response :not_found
    get admin_ship_path(@ship)
    assert_response :not_found
    post review_admin_ship_path(@ship), params: { decision: "approved" }
    assert_response :not_found
    post fraud_admin_ship_path(@ship), params: { verdict: "pass" }
    assert_response :not_found
    post send_back_admin_ship_path(@ship), params: { reason: "x" }
    assert_response :not_found
    assert @ship.reload.in_review?
  end

  test "a stored javascript: link shows as text, never as a link" do
    @ship.update_columns(repo_url: "javascript://x.example/%0Aalert(1)", demo_url: "data://text/html,<script>alert(1)</script>")
    projects(:ana).update_columns(repo_url: "javascript://x.example/%0Aalert(2)")
    sign_in_as(users(:orpheus))

    get admin_ship_path(@ship)
    assert_response :success
    assert_select "a[href^=javascript], a[href^=data]", 0
    assert_select ".ash__unsafe-link", text: "javascript://x.example/%0Aalert(1)"
    assert_select ".ash__unsafe-link", text: "data://text/html,<script>alert(1)</script>"
    assert_select "a#admin-ship-repo-link", 0

    get admin_project_path(projects(:ana))
    assert_response :success
    assert_select "a[href^=javascript]", 0
    assert_select "dd", text: "javascript://x.example/%0Aalert(2)"
  end

  test "the approve form starts at the most the handbook allows, and shows why (D-030)" do
    @ship.update_columns(ai_coding_seconds: 90 * 60, art_seconds: 0)
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_response :success
    assert_select "#admin-ship-limits", text: /Claimed\s*7\.5 hrs\s*Counted.*?7\.5 hrs.*AI coding.*1\.5 hrs\s*−1.*Art \(designing and Lapse\).*0 hrs.*Most to approve\s*6\.5 hrs/m
    assert_select "input[name=coding_hours][value='6.5'][max='6.5']"
    assert_select "input[name=art_hours]", 0, "no art, no art field"
    assert_select "textarea[name=deflation_reason]", ""
    assert_select "textarea[name=technical_features]", ""
    assert_select "[data-limits=unknown]", 0

    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "7.5", technical_features: "A second ball with its own physics." }
    assert_redirected_to admin_ship_path(@ship), "the AI cut needs no reason"
    @ship.reload
    assert_equal BigDecimal("6.5"), @ship.review_hours, "held to the limit"
    assert_equal BigDecimal("7.5"), @ship.claimed_hours
    assert_match(/AI coding on this game, which counts at a third/, @ship.deflation_reason, "the limits' words go to Airtable")
  end

  # D-111: a participant's ship of 5.3 counted hours with 5542 s of art. The form's own figures, posted back as they are, store the
  # 5.3 claimed and ask for no reason: they were 3.76 and 1.53 once, which made 5.29.
  test "the form's own figures, posted back, store the hours claimed and ask for no reason (D-111)" do
    unified_ysws_has_no_record
    users(:ana).streak_activities.update_all(coded_seconds: 19_080)
    @ship.update_columns(hours: 5.3, ai_coding_seconds: 0, art_seconds: 5542)
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_response :success
    assert_select "#admin-ship-limits", text: /Claimed\s*5\.3 hrs.*Most to approve\s*5\.3 hrs/m
    coding = css_select("input[name=coding_hours]").first["value"]
    art = css_select("input[name=art_hours]").first["value"]
    assert_equal [ "3.76", "1.54" ], [ coding, art ]
    assert_select "[data-deflate-target=why][hidden]", 1, "no reason is due on the defaults"

    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: coding, art_hours: art, technical_features: "Two-ball physics." }
    assert_redirected_to admin_ship_path(@ship)
    @ship.reload
    assert_equal [ BigDecimal("5.3"), BigDecimal("5.3") ], [ @ship.claimed_hours, @ship.review_hours ]
    assert_nil @ship.deflation_reason

    post fraud_admin_ship_path(@ship), params: { verdict: "pass" }
    assert_equal BigDecimal("5.3"), @ship.reload.approved_hours
    get admin_ship_path(@ship)
    assert_select "#admin-ship-deflation-problem", 0
    assert_select "#admin-ship-airtable", { text: /Deflation Justification/, count: 0 }, "nothing was deflated"
  end

  test "a reason is due once a figure goes below the most, even by a hundredth (D-111)" do
    users(:ana).streak_activities.update_all(coded_seconds: 19_080)
    @ship.update_columns(hours: 5.3, ai_coding_seconds: 0, art_seconds: 5542)
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "3.75", art_hours: "1.54", technical_features: "Two-ball physics." }
    assert_response :unprocessable_entity
    assert_select ".ash__error", "Say why you approve fewer hours than the rules allow"
    assert_select "[data-deflate-target=why]:not([hidden])", 1, "the box for it is open"
    assert @ship.reload.in_review?

    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "3.75", art_hours: "1.54", technical_features: "Two-ball physics.",
                                                  deflation_reason: "A menu was cut." }
    assert_redirected_to admin_ship_path(@ship)
    assert_equal [ BigDecimal("3.75"), BigDecimal("1.53"), "A menu was cut." ], [ @ship.reload.review_coding_hours, @ship.review_art_hours, @ship.deflation_reason ],
                 "the art is held to its share of the coding, rounded down"
  end

  test "an approved ship with a cut that has no reason is not sent, and the page says so (D-111)" do
    unified_ysws_has_no_record
    @ship.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 0, hours: 10)
    users(:ana).streak_activities.update_all(coded_seconds: 10 * 3600)
    limits_say = @ship.limits(10).reason
    # The limits cut 3 of the 10 hours claimed (AI coding at a third: 10 less 2). The reviewer took 5 more and wrote nothing.
    @ship.update_columns(approved_columns(5, claimed_hours: 10, review_coding_hours: 5, review_art_hours: 0, deflation_reason: limits_say,
                                          decided_by_id: users(:orpheus).id, decided_at: Time.current))
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_response :success
    assert_select "#admin-ship-deflation-problem[role=alert]", /Not sent to Airtable: the reviewer's cut of 3 hrs has no reason\. Every deflation needs a reason\./
    assert_select "#admin-ship-airtable", { text: /Deflation Justification/, count: 0 }

    @ship.update_columns(deflation_reason: "#{limits_say} A menu was cut.")
    get admin_ship_path(@ship)
    assert_select "#admin-ship-deflation-problem", 0
    assert_select "#admin-ship-airtable", /Deflation Justification\s*Deflated from 10 to 5 hours: .*The reviewer's reason: A menu was cut\./m
  end

  test "approving without the technical features or a reason comes back with what was typed" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "5", technical_features: " ", deflation_reason: "" }
    assert_response :unprocessable_entity
    assert @ship.reload.in_review?
    assert_select ".ash__error", "Name the specific technical features that explain the hours"
    assert_select ".ash__error", "Say why you approve fewer hours than the rules allow"
    assert_select "input[name=coding_hours][value='5.0']"

    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "5", technical_features: "Two-ball physics.", deflation_reason: "" }
    assert_response :unprocessable_entity
    assert_select "textarea[name=technical_features]", "Two-ball physics."
    assert_select ".ash__error", 1
  end

  test "without Hackatime's AI coding and art time the page says no cut applies" do
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_select "[data-limits=unknown]", /no cut applies/
    assert_select "#admin-ship-limits dd", /unknown/
    assert_select "input[name=coding_hours][value='7.5']"
  end

  test "an approved ship shows what goes to Airtable, with the duplicate justification, and a later record warns of overlap" do
    Ship::EarlierShip.token = "pat-test"
    records = [ { fields: { "Code URL" => "https://github.com/ana/pong", "YSWS–Name" => [ "jame gam" ], "Approved At" => "2026-10-24", "Override Hours Spent" => 4 } } ]
    Web.adapter = lambda do |_method, url, _headers|
      body = URI(url).host == "api.github.com" ? [].to_json : { records: }.to_json
      Web::Response.new(status: 200, headers: {}, body:)
    end
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_select "[data-overlap]", /jame gam record was approved after this project's hours began counting/

    approve_through_fraud(@ship, technical_features: "Two-ball physics.")
    get admin_ship_path(@ship)
    assert_select "#admin-ship-airtable", /Specific Technical Features\s*Two-ball physics\./
    assert_select "#admin-ship-airtable", /Duplicate Justification\s*This code URL is already in the Unified YSWS DB: jame gam \(approved 10\/24\/2026, 4 hours\)/
    assert_select "#admin-ship-airtable", /Hackatime Project Name\(s\) \+ Date Range\(s\)\s*pong 10\/23\/2026-/
    assert_select "#admin-ship-airtable", { text: /Override Hours Spent Justification/, count: 0 }
  end

  test "the evidence panels show the hours per Hackatime project, the repo and its old release, and the participant (D-063)" do
    sign_in_as(users(:orpheus))
    @ship.update_columns(hackatime_projects: [ "Gloobls", "Halloween Game" ], hackatime_seconds: { "Gloobls" => 1800, "Halloween Game" => 3600 })
    users(:ana).update_columns(hackatime_uid: "1001", hackatime_access_token: "token-orpheus", hackatime_trust_level: "yellow")
    original = Hackatime.method(:project_seconds)
    Hackatime.define_singleton_method(:project_seconds) { |_user, names, _times| names.index_with { 7200 } }
    Web.adapter = lambda do |_method, url, _headers|
      body = case URI(url).path
      when "/repos/ana/pong" then { full_name: "ana/pong", pushed_at: "2026-10-24T00:00:00Z", stargazers_count: 2 }
      when "/repos/ana/pong/releases/latest"
        { tag_name: "v0.1", html_url: "https://github.com/ana/pong/releases/tag/v0.1", published_at: "2026-10-01T00:00:00Z", assets: [ { name: "pong.zip", size: 2048 } ] }
      else []
      end
      Web::Response.new(status: 200, headers: {}, body: body.to_json)
    end

    get admin_ship_path(@ship)

    assert_response :success
    assert_select "#admin-ship-hackatime-hours tbody tr", 2
    assert_select "#admin-ship-hackatime-hours tr", text: /Gloobls\s*0\.5 hrs\s*2 hrs/
    assert_select "#admin-ship-hackatime-hours tfoot", /Claimed\s*7\.5 hrs/
    assert_select "#admin-ship-repo-facts", /ana\/pong/
    assert_select "#admin-ship-repo-facts", /v0\.1.*published Oct 1, 2026.*pong\.zip.*2 KB/m
    assert_select "[data-release=predates]", /before/
    assert_select "#admin-ship-participant", /ana@hackclub\.com.*verified/m
    assert_select "#admin-ship-person summary [data-trust=yellow]", "trust yellow"
    assert_select "#admin-ship-participant a[href='https://hackclub.slack.com/team/U0ANA']"
    assert_select "#admin-ship-telescreen[href='https://telescreen.hackclub.com/workbench/hackatime/overview?u=1001&p=Gloobls,Halloween+Game']"
    assert_select "#admin-ship-lapse-review[href='https://telescreen.hackclub.com/workbench/lapse?u=1001']"
    assert_select "[data-lapses=unavailable]", /session list is unavailable.*admin API key/
  ensure
    Hackatime.define_singleton_method(:project_seconds, original) if original
  end

  test "a failing GitHub or Hackatime leaves the page up with a line saying so" do
    sign_in_as(users(:orpheus))
    users(:ana).update_columns(hackatime_uid: "1001", hackatime_access_token: "token-orpheus")
    original = Hackatime.method(:project_seconds)
    Hackatime.define_singleton_method(:project_seconds) { |*| raise Hackatime::Unavailable, "down" }
    Web.adapter = ->(*) { raise Web::Error, "boom" }

    get admin_ship_path(@ship)

    assert_response :success
    assert_select "[data-hackatime=problem]", /couldn't be reached/
    assert_select "[data-repo=error]", /GitHub couldn't be reached/
    assert_select "h1", "Pong"
    assert_select "form#verdict[action=?]", review_admin_ship_path(@ship)
  ensure
    Hackatime.define_singleton_method(:project_seconds, original) if original
  end

  test "a repo shared with another account shows a warning box" do
    sign_in_as(users(:orpheus))
    projects(:orpheus).update_columns(repo_url: "https://github.com/ana/pong")

    get admin_ship_path(@ship)
    assert_select "#admin-ship-duplicate-list", /Orpheus the Dino.*same repository/m

    projects(:orpheus).update_columns(repo_url: "https://github.com/orpheus/other")
    get admin_ship_path(@ship)
    assert_select "#admin-ship-duplicates", 0
  end

  test "the Stardance check shows a banner when the repo is shipped there, and a quiet line when it can't be read" do
    sign_in_as(users(:orpheus))
    token = ENV["STARDANCE_MCP_TOKEN"]
    ENV["STARDANCE_MCP_TOKEN"] = nil
    get admin_ship_path(@ship)
    assert_select "[data-stardance=unknown]", /Could not check Stardance \(no STARDANCE_MCP_TOKEN set\)/
    assert_select "[data-stardance=shipped]", 0

    ENV["STARDANCE_MCP_TOKEN"] = "token-test"
    Web.adapter = lambda do |_method, _url, _headers, body = nil|
      next Web::Response.new(status: 200, headers: {}, body: "[]") unless body # the repo's page, not Stardance

      message = JSON.parse(body)
      next Web::Response.new(status: 202, headers: {}, body: "") unless message["id"]

      text = case message.dig("params", "name")
      when "query" then "Query ID: q\nTotal rows: 1\nColumns: repo, project_id"
      when "get_rows" then "Rows 1-1 of 1:\n\nrepo | project_id\n----\n#{"https://github.com/ana/pong".unpack1("H*")} | 74"
      end
      result = message["method"] == "initialize" ? { protocolVersion: "2025-06-18" } : { content: [ { type: "text", text: } ] }
      Web::Response.new(status: 200, headers: {}, body: { jsonrpc: "2.0", id: message["id"], result: }.to_json)
    end
    get admin_ship_path(@ship)
    assert_response :success
    assert_select "[data-stardance=shipped]", /shipped on Stardance.*Approve is off/m
    assert_select "[data-stardance=shipped] a[href='https://stardance.hackclub.com/projects/74']"
  ensure
    ENV["STARDANCE_MCP_TOKEN"] = token
  end

  # Claims (D-063).

  test "opening a ship takes the claim, and another admin sees who holds it, with a way to take over" do
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    claim = Claim.find_by!(ship: @ship, stage: "review")
    assert_equal users(:orpheus), claim.user
    assert_select "[data-controller=heartbeat][data-heartbeat-stage-value=review] #admin-ship-claim[hidden]"

    sign_in_as(@heidi)
    get admin_ship_path(@ship)
    assert_select "#admin-ship-claim:not([hidden])", /Orpheus is working on this review/
    assert_select "#admin-ship-claim a[href=?]", admin_ship_path(@ship, take: 1), "Take over"
    assert_equal users(:orpheus), claim.reload.user, "looking does not take it"

    get admin_ship_path(@ship, take: 1)
    assert_equal @heidi, claim.reload.user
    assert_select "#admin-ship-claim[hidden]"
  end

  test "a verdict while another admin holds the ship is refused" do
    Claim.acquire(@ship, "review", users(:orpheus))
    sign_in_as(@heidi)
    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "Add a README." }
    assert_redirected_to admin_ship_path(@ship)
    assert_equal "Someone else holds this ship.", flash[:alert]
    assert @ship.reload.in_review?

    travel_to(2.minutes.from_now) do
      post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "Add a README." }
      assert @ship.reload.changes_needed?, "a stale claim is anyone's"
    end
  end

  test "a fraud verdict and a send-back are refused while another admin holds the fraud check" do
    @ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", review_hours: 5)
    Claim.acquire(@ship, "fraud", users(:orpheus))
    sign_in_as(@heidi)
    post fraud_admin_ship_path(@ship), params: { verdict: "pass" }
    assert_equal "Someone else holds this ship.", flash[:alert]
    post send_back_admin_ship_path(@ship), params: { reason: "Hours look high." }
    assert_equal "Someone else holds this ship.", flash[:alert]
    assert @ship.reload.awaiting_fraud?
  end

  test "a verdict clears the claim" do
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_equal 1, @ship.claims.count
    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "Add a README." }
    assert_equal 0, @ship.claims.count
  end

  test "the heartbeat keeps a claim, and says who has it when someone took over" do
    sign_in_as(users(:orpheus))
    post admin_claims_heartbeat_path, params: { id: @ship.id, stage: "review" }
    assert_equal({ "ok" => true, "holder" => "Orpheus" }, response.parsed_body)

    Claim.acquire(@ship, "review", @heidi, force: true)
    post admin_claims_heartbeat_path, params: { id: @ship.id, stage: "review" }
    assert_equal({ "ok" => false, "holder" => "Heidi" }, response.parsed_body)

    post admin_claims_heartbeat_path, params: { id: @ship.id, stage: "review", force: 1 }
    assert_equal true, response.parsed_body["ok"]
    post admin_claims_heartbeat_path, params: { id: @ship.id, stage: "nonsense" }
    assert_response :forbidden
  end

  # The hours start (D-065).

  test "the hours start panel names a jame gam submission as the source (D-066)" do
    sign_in_as(users(:orpheus))
    projects(:ana).update_columns(jame_gam_submitted_at: Time.utc(2026, 10, 25, 10), jame_gam_review_status: "Pending")
    get admin_ship_path(@ship)
    assert_select "#hours-start", /Oct 25, 10:00 UTC\s+\(jame gam submission \(Pending, Oct 25\)\)/
  end

  test "the review page shows where the hours start from, and an admin sets and clears an override" do
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)
    assert_select "#hours-start", /Hours count from\s+Oct 23, \d\d:\d\d UTC\s+\(launch\)/
    assert_select "form[action=?] input[type=datetime-local]", hours_start_admin_ship_path(@ship)

    travel_to(Program::STARTS_AT + 3.days) do
      assert_difference -> { AdminAuditEvent.where(tool: "set_hours_start").count }, 1 do
        patch hours_start_admin_ship_path(@ship), params: { hours_start_override: (Program::STARTS_AT + 1.day).utc.strftime("%Y-%m-%dT%H:%M") }
      end
      assert_redirected_to admin_ship_path(@ship)
      assert_equal (Program::STARTS_AT + 1.day).change(sec: 0), projects(:ana).reload.hours_start_override
      assert_equal({ "ship_id" => @ship.id, "project_id" => projects(:ana).id }, AdminAuditEvent.where(tool: "set_hours_start").last.ids)

      get admin_ship_path(@ship)
      assert_select "#hours-start", /\(set by a reviewer\)/
      assert_select "button[name=clear]"

      patch hours_start_admin_ship_path(@ship), params: { clear: "1" }
      assert_nil projects(:ana).reload.hours_start_override
      assert_equal 2, AdminAuditEvent.where(tool: "set_hours_start").count
    end
  end

  test "an override before the launch, in the future, or not a time is refused" do
    sign_in_as(users(:orpheus))
    travel_to(Program::STARTS_AT + 3.days) do
      patch hours_start_admin_ship_path(@ship), params: { hours_start_override: (Program::STARTS_AT - 1.day).utc.strftime("%Y-%m-%dT%H:%M") }
      assert_match(/before Save Point began/, flash[:alert])
      patch hours_start_admin_ship_path(@ship), params: { hours_start_override: (Time.current + 1.day).utc.strftime("%Y-%m-%dT%H:%M") }
      assert_match(/in the future/, flash[:alert])
      patch hours_start_admin_ship_path(@ship), params: { hours_start_override: "tomorrow-ish" }
      assert_match(/Pick a date and time/, flash[:alert])
      assert_nil projects(:ana).reload.hours_start_override
    end
  end

  test "only an admin sets the hours start, and not on their own ship" do
    patch hours_start_admin_ship_path(@ship), params: { clear: "1" }
    assert_not_equal 200, response.status

    outsider = User.create!(hca_id: "ident!zed", email: "zed@hackclub.com", name: "Zed", first_name: "Zed", slack_id: "U0ZED")
    sign_in_as(outsider)
    patch hours_start_admin_ship_path(@ship), params: { hours_start_override: (Program::STARTS_AT + 1.day).utc.strftime("%Y-%m-%dT%H:%M") }
    assert_response :not_found
    assert_nil projects(:ana).reload.hours_start_override

    sign_in_as(users(:ana))
    travel_to(Program::STARTS_AT + 3.days) do
      patch hours_start_admin_ship_path(@ship), params: { hours_start_override: (Program::STARTS_AT + 1.day).utc.strftime("%Y-%m-%dT%H:%M") }
      assert_equal "Someone else judges your own ship.", flash[:alert]
      assert_nil projects(:ana).reload.hours_start_override
    end
  end

  # Your own ship (D-063).

  test "an admin can't review, fraud-check or send back their own ship" do
    sign_in_as(users(:ana))
    get admin_ship_path(@ship)
    assert_response :success
    assert_select "[data-own=true]", /your own ship/
    assert_select "form#verdict", 0
    assert_select "a[data-shortcut=n]", 0
    assert_equal 0, @ship.claims.count, "no claim on your own"

    post review_admin_ship_path(@ship), params: { decision: "approved", technical_features: "Mine." }
    assert_redirected_to admin_ship_path(@ship)
    assert_equal "Someone else judges your own ship.", flash[:alert]
    assert @ship.reload.in_review?
    patch checklist_admin_ship_path(@ship), params: { key: "runs", value: "1" }
    assert_response :forbidden

    @ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", review_hours: 5)
    post fraud_admin_ship_path(@ship), params: { verdict: "pass" }
    assert_equal "Someone else judges your own ship.", flash[:alert]
    post send_back_admin_ship_path(@ship), params: { reason: "Mine." }
    assert_equal "Someone else judges your own ship.", flash[:alert]
    assert @ship.reload.awaiting_fraud?
    post admin_claims_heartbeat_path, params: { id: @ship.id, stage: "fraud" }
    assert_response :forbidden
  end

  # The queues (D-063).

  test "the review queue opens the oldest ship waiting, and skip moves on to the next" do
    newer = projects(:orpheus).ships.create!(@ship.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 3, screenshot: screenshot_upload, screenshot_shows_game: true))
    older = projects(:orpheus).ships.create!(@ship.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 3, screenshot: screenshot_upload, screenshot_shows_game: true))
    older.update_columns(created_at: @ship.created_at - 1.day)
    newer.update_columns(created_at: @ship.created_at + 1.day)
    sign_in_as(@heidi)

    get admin_review_path
    assert_redirected_to admin_ship_path(older, queue: 1)
    get admin_review_path(skip: older.id)
    assert_redirected_to admin_ship_path(@ship, queue: 1)
    get admin_review_path(skip: @ship.id)
    assert_redirected_to admin_ship_path(newer, queue: 1)
    get admin_review_path(skip: newer.id)
    assert_response :success
    assert_select "#admin-queue-empty", /Nothing left for you: 3 waiting/
    assert_select "a[href=?]", admin_review_path(reset: 1), /Start again \(3 skipped\)/
    get admin_review_path(reset: 1)
    assert_redirected_to admin_ship_path(older, queue: 1)
  end

  test "the queues leave out your own ships, and ones another admin holds" do
    mine = projects(:orpheus).ships.create!(@ship.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 3, screenshot: screenshot_upload, screenshot_shows_game: true))
    mine.update_columns(created_at: @ship.created_at - 1.day)
    sign_in_as(users(:orpheus))
    get admin_review_path
    assert_redirected_to admin_ship_path(@ship, queue: 1), "not the older one: it is Orpheus's own"

    Claim.acquire(@ship, "review", @heidi)
    get admin_review_path
    assert_response :success
    assert_select "#admin-queue-empty", /Nothing left for you/
    get admin_ships_path
    assert_select "a[href=?]", admin_review_path
  end

  test "the fraud queue opens the oldest ship waiting for its fraud check" do
    sign_in_as(users(:orpheus))
    get admin_fraud_path
    assert_response :success
    assert_select "#admin-queue-empty", /Nothing's waiting/

    @ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", review_hours: 5, reviewed_at: Time.current)
    get admin_fraud_path
    assert_redirected_to admin_ship_path(@ship, queue: 1)
  end

  test "a verdict from the queue goes on to the next ship in it" do
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "Add a README.", queue: 1 }
    assert_redirected_to admin_review_path
    @ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", review_hours: 5)
    post fraud_admin_ship_path(@ship), params: { verdict: "pass", queue: 1 }
    assert_redirected_to admin_fraud_path
  end

  test "Approve is off, on the page and on a direct post, while the repo is shipped on Stardance (D-063)" do
    sign_in_as(users(:orpheus))
    Ship::Evidence.alias_method :original_stardance_shipped?, :stardance_shipped?
    Ship::Evidence.define_method(:stardance_shipped?) { true }

    get admin_ship_path(@ship)
    assert_select "form#verdict button[data-verdict=approved][disabled]"
    assert_select "form#verdict button[data-verdict=changes_needed]:not([disabled])"

    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "6", technical_features: "A second ball." }
    assert_redirected_to admin_ship_path(@ship)
    assert_match(/shipped on Stardance/, flash[:alert])
    assert @ship.reload.in_review?

    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "Ship it on Stardance instead." }
    assert @ship.reload.changes_needed?, "changes needed stays open"
  ensure
    Ship::Evidence.alias_method :stardance_shipped?, :original_stardance_shipped?
    Ship::Evidence.remove_method :original_stardance_shipped?
  end

  # D-097, D-101: a ship of a project with an earlier approved ship. The earlier one holds 3 hrs (3 coding), made a day and a half in.
  def make_later_ship
    travel_to(Program::STARTS_AT + 1.5.days) do
      @earlier = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                                              changes_made: "First version.", repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong",
                                              hackatime_projects: [ "pong" ], hours: 3, screenshot: screenshot_upload, screenshot_shows_game: true)
    end
    @earlier.update_columns(status: "approved", approved_hours: 3, review_hours: 3, review_coding_hours: 3, review_art_hours: 0, decided_by_id: users(:ana).id, decided_at: Time.current)
    @ship.update_columns(ai_coding_seconds: 90 * 60, art_seconds: 2 * 3600)
  end

  test "a later ship's form shows the earlier approval as fixed and takes only the new hours (D-097)" do
    make_later_ship
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)

    assert_response :success
    assert_select "#admin-ship-already-approved", "Already approved: 3 hrs (#{@earlier.created_at.strftime("%b %-d")} ship)"
    # 7.5 counted, art 2, AI 1.5: the project's coding cap is 4.5, so 1.5 more than the 3 used; art held at 1.92 beside 4.5 coding.
    assert_select "label[for=coding_hours]", "New coding hours"
    assert_select "label[for=art_hours]", "New art hours"
    assert_select "input[name=coding_hours][value='1.5'][max='1.5']"
    assert_select "input[name=art_hours][value='1.92']"
    assert_select "[data-deflate-target=total]", "6.42"
    assert_select "#verdict-submit", /Approve\s*6\.42\s*hrs in all/
    assert_select "form#verdict[data-deflate-earlier-coding-value='3.0'][data-deflate-earlier-art-value='0.0']"
  end

  test "a first ship's form has no already-approved line, and keeps its labels (D-097)" do
    sign_in_as(users(:orpheus))
    get admin_ship_path(@ship)

    assert_select "#admin-ship-already-approved", 0
    assert_select "label[for=coding_hours]", "Coding hours"
    assert_select "#admin-ship-last-approved", 0
    assert_select "#admin-ship-commits-toggle", 0
  end

  test "approving a later ship adds the new hours to the earlier approval, and a pass spends the total (D-097)" do
    make_later_ship
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "1", art_hours: "0.5", technical_features: "A second ball.",
                                                  deflation_reason: "Less than allowed." }
    assert_redirected_to admin_ship_path(@ship)
    @ship.reload
    assert @ship.awaiting_fraud?
    assert_equal [ 4, BigDecimal("0.5"), BigDecimal("4.5") ], [ @ship.review_coding_hours, @ship.review_art_hours, @ship.review_hours ]

    follow_redirect!
    assert_select "#admin-ship-review-already", /Already approved.*3 hrs/m
    assert_select "#admin-ship-review-new", /New hours from review.*1\.5 hrs/m
    assert_select "#admin-ship-review-said .ash__limits-total", /4\.5 hrs/
    assert_select "input[name=deduct_hours][max='1.5']"

    post fraud_admin_ship_path(@ship), params: { verdict: "pass" }
    assert_equal BigDecimal("4.5"), @ship.reload.approved_hours
    assert_equal 4.5, projects(:ana).reload.hours_approved

    get admin_ship_path(@ship)
    assert_select "#admin-ship-decided-already", /3 hrs/
    assert_select "#admin-ship-decided-new", /1\.5 hrs/
    assert_select "#admin-ship-review-hours", /Review approved, total.*4\.5 hrs/m
  end

  test "a send-back of a later ship refills the new hours from the earlier review (D-097)" do
    make_later_ship
    sign_in_as(users(:orpheus))
    post review_admin_ship_path(@ship), params: { decision: "approved", coding_hours: "1", art_hours: "0.5", technical_features: "A second ball.",
                                                  deflation_reason: "Less than allowed." }
    post send_back_admin_ship_path(@ship), params: { reason: "Check the art hours." }
    assert @ship.reload.in_review?

    get admin_ship_path(@ship)
    assert_select "input[name=coding_hours][value='1.0']"
    assert_select "input[name=art_hours][value='0.5']"
    assert_select "[data-deflate-target=total]", "4.5"
  end

  test "a later ship lists the commits since the last approved ship, with a link to all, and shows both screenshots (D-101)" do
    make_later_ship
    sign_in_as(users(:orpheus))
    before = (Program::STARTS_AT + 1.day).utc.iso8601
    after = (Program::STARTS_AT + 1.75.days).utc.iso8601
    Web.adapter = lambda do |_method, url, _headers|
      if URI(url).host == "api.github.com" && url.include?("/commits?")
        Web::Response.new(status: 200, headers: {}, body: [
          { sha: "bbbbbbb1111", html_url: "https://github.com/ana/pong/commit/bbbbbbb", commit: { message: "Newer work", author: { name: "Ana", date: after } } },
          { sha: "aaaaaaa1111", html_url: "https://github.com/ana/pong/commit/aaaaaaa", commit: { message: "Older work", author: { name: "Ana", date: before } } }
        ].to_json)
      else
        Web::Response.new(status: 404, headers: {}, body: "{}")
      end
    end
    get admin_ship_path(@ship)

    assert_select "#admin-ship-commits", /Commits since the last approved ship/
    assert_select ".ash__commit", 1
    assert_select ".ash__commit", /Newer work/
    assert_select ".ash__commits-note", /1 from #{@earlier.created_at.utc.strftime("%b %-d")}/
    assert_select "a#admin-ship-commits-toggle[href=?]", admin_ship_path(@ship, commits: "all"), /Show all commits since/
    assert_select "#admin-ship-last-approved figcaption", /Last approved ship\s*#{@earlier.created_at.utc.strftime("%b %-d")}/
    assert_select "#admin-ship-screenshots figcaption", /This ship\s*#{@ship.created_at.utc.strftime("%b %-d")}/
    assert_select "#admin-ship-last-approved img[alt^='Screenshot of the last approved ship']"
    assert_select "#admin-ship-screenshots img[alt^='Screenshot of this ship']"
    assert_select "#admin-ship-screenshots h2", 1, "one panel for the screenshots"

    get admin_ship_path(@ship, commits: "all")
    assert_select "#admin-ship-commits", /Commits since Save Point began/
    assert_select ".ash__commit", 2
    assert_select "a#admin-ship-commits-toggle", "Show only since the last approved ship"
  end

  test "the review queue labels a later ship as an update with its new hours, and leaves a first ship alone (D-101)" do
    sign_in_as(users(:orpheus))
    get admin_ships_path
    assert_select "tr##{dom_id(@ship)} [data-update]", 0

    make_later_ship
    get admin_ships_path
    assert_select "tr##{dom_id(@ship)} [data-update]", "Update · +4.5 hrs"
    assert_select "tr##{dom_id(@earlier)} [data-update]", 0
  end

  # D-109: a ship the participant replaced by shipping again.

  test "a verdict on a replaced ship is refused with why, and the heartbeat tells the page to reload" do
    sign_in_as(@heidi)
    get admin_ship_path(@ship)
    assert_select "[data-controller=heartbeat]"
    newer = projects(:ana).ship!(title: "Pong 2", description: "Two paddles, one ball, and every frame is a sprite.", changes_made: "More.",
                                 repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", screenshot_shows_game: true,
                                 screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"))
    assert @ship.reload.superseded?

    post review_admin_ship_path(@ship), params: { decision: "approved", technical_features: "A second ball." }
    assert_redirected_to admin_ship_path(@ship)
    assert_equal Ship::REPLACED_MESSAGE, flash[:alert]
    post review_admin_ship_path(@ship), params: { decision: "changes_needed", review_feedback: "More." }
    assert_equal Ship::REPLACED_MESSAGE, flash[:alert]
    post review_admin_ship_path(@ship), params: { decision: "banned", evidence: "Copied." }
    assert_equal Ship::REPLACED_MESSAGE, flash[:alert]
    assert @ship.reload.superseded?, "no verdict was applied"
    assert_not users(:ana).reload.banned?

    post admin_claims_heartbeat_path, params: { id: @ship.id, stage: "review" }
    assert_equal({ "ok" => false, "replaced" => true, "holder" => nil }, response.parsed_body)
    assert_equal 0, @ship.claims.count, "a replaced ship takes no claim"

    get admin_ship_path(@ship)
    assert_select "[data-replaced]", /The participant shipped again, so this ship was replaced/
    assert_select "[data-replaced] a[href=?]", admin_ship_path(newer)
    assert_select "form[action=?]", review_admin_ship_path(@ship), 0
  end

  test "a reviewer who opened the verdict page before the ship was replaced has the claim removed, and the queue skips it" do
    sign_in_as(@heidi)
    get admin_ship_path(@ship)
    assert_equal 1, @ship.claims.count
    newer = projects(:ana).ship!(title: "Pong 2", description: "Two paddles, one ball, and every frame is a sprite.", changes_made: "More.",
                                 repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", screenshot_shows_game: true,
                                 screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"))
    assert_equal 0, @ship.claims.count

    get admin_review_path
    assert_redirected_to admin_ship_path(newer, queue: 1)
  end

  test "the ships list shows a replaced ship plainly, and its own tab" do
    newer = projects(:ana).ship!(title: "Pong 2", description: "Two paddles, one ball, and every frame is a sprite.", changes_made: "More.",
                                 repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", screenshot_shows_game: true,
                                 screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"))
    sign_in_as(@heidi)
    get admin_ships_path
    assert_select "tr##{dom_id(@ship)}[data-status=superseded] .pg-admin-ships__status", "Replaced"
    assert_select "tr##{dom_id(@ship)} small", /by a newer ship/
    assert_select "#admin-ships-review ~ .pg-admin-ships__panel tr##{dom_id(@ship)}", 0
    assert_select "a[data-stage=superseded]", /Replaced\s*1/
    get admin_ships_path(stage: "superseded")
    assert_select "tr##{dom_id(@ship)}"
    assert_select "tr##{dom_id(newer)}", 0
  end

  test "a ship behind an earlier one in its fraud check is not offered to a reviewer, and its verdict waits" do
    @ship.decide!("approved", by: @heidi, technical_features: "A second ball.")
    assert @ship.reload.awaiting_fraud?
    later = projects(:ana).ship!(title: "Pong 2", description: "Two paddles, one ball, and every frame is a sprite.", changes_made: "More.",
                                 repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", screenshot_shows_game: true,
                                 screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"))
    sign_in_as(@heidi)
    get admin_review_path
    assert_response :success
    assert_select "#admin-queue-empty"
    get admin_ship_path(later)
    assert_select "[data-waiting-on-earlier]", /still in its fraud check/
    post review_admin_ship_path(later), params: { decision: "changes_needed", review_feedback: "More." }
    assert_response :unprocessable_entity
    assert later.reload.in_review?
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end

    def screenshot_upload
      Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")
    end

    # The Unified YSWS DB answers with no earlier record of the game, so the page draws the fields the sync would send.
    def unified_ysws_has_no_record
      Ship::EarlierShip.token = "pat-test"
      Web.adapter = lambda do |_method, url, _headers|
        body = URI(url).host == "api.github.com" ? [].to_json : { records: [] }.to_json
        Web::Response.new(status: 200, headers: {}, body:)
      end
    end
end
