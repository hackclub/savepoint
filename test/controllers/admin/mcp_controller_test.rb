require "test_helper"
require_relative "../../support/admin_mcp_helpers"

class Admin::McpControllerTest < ActionDispatch::IntegrationTest
  include AdminMcpHelpers
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @token, @record = mcp_token_for
    create_insights_views # admin_summary reads the participants' funnel from them
  end

  teardown do
    Rails.configuration.x.admin_slack_ids = @admins
    Web.adapter = nil
  end

  test "no token, a bad token, a revoked token and a non-admin's token are all not found" do
    mcp_post(nil, "ping")
    assert_response :not_found

    mcp_post("spat_nope", "ping")
    assert_response :not_found

    mcp_post("spat_#{SecureRandom.urlsafe_base64(32)}", "ping")
    assert_response :not_found

    ana_token, = mcp_token_for(users(:ana))
    mcp_post(ana_token, "ping")
    assert_response :not_found

    @record.revoke!
    mcp_post(@token, "ping")
    assert_response :not_found
    assert_equal 0, AdminAuditEvent.count
  end

  test "a token stops working when its owner is no longer an admin" do
    mcp_post(@token, "ping")
    assert_response :success
    Rails.configuration.x.admin_slack_ids = []
    mcp_post(@token, "ping")
    assert_response :not_found
  end

  test "a good token initializes, and says who it's for" do
    mcp_post(@token, "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } })
    assert_response :success
    result = response.parsed_body["result"]
    assert_equal "savepoint", result.dig("serverInfo", "name")
    assert_match(/teenagers: share only what the task needs/, result["instructions"])
    assert_match(/confirm each with the human first/, result["instructions"])
    assert_not_nil @record.reload.last_used_at

    mcp_post(@token, "notifications/initialized", id: nil)
    assert_response :accepted
  end

  test "tools/list offers every tool, and the write tools say to confirm first" do
    mcp_post(@token, "tools/list")
    tools = response.parsed_body.dig("result", "tools").index_by { it["name"] }

    assert_equal %w[admin_summary audit_log credit_shop_hours decide_extension describe_schema edit_review_text edit_snapshot find_people find_projects find_ships funnel get_person get_project get_ship
                    list_extensions list_orders mark_order_ordered metrics nudges public_stats query_sql save_review_draft send_verdict_dm set_checklist_item set_hours_start set_lapse_coding set_reviewer_ai set_ship_until set_shop_until], tools.keys.sort
    writes = %w[save_review_draft set_lapse_coding set_reviewer_ai set_checklist_item set_hours_start edit_snapshot edit_review_text send_verdict_dm mark_order_ordered decide_extension set_ship_until credit_shop_hours set_shop_until]
    writes.each do |name|
      assert tools[name]["description"].start_with?("Changes real data: confirm with the human first."), name
      assert_equal false, tools[name].dig("annotations", "readOnlyHint")
    end
    (tools.keys - writes).each do |name|
      assert_not tools[name]["description"].include?("Changes real data"), name
      assert_equal true, tools[name].dig("annotations", "readOnlyHint")
    end
  end

  test "GET and DELETE are not allowed, and still need a token" do
    get admin_mcp_path
    assert_response :not_found
    get admin_mcp_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :method_not_allowed
    assert_equal "POST", response.headers["Allow"]
    delete admin_mcp_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :method_not_allowed
  end

  test "the session cookie does not work here" do
    mock_hack_club_auth(uid: "ident!orpheus", slack_id: "U0ORPHEUS", email: "orpheus@hackclub.com", name: "Orpheus", first_name: "Orpheus")
    post "/auth/hackclub"
    follow_redirect!
    mcp_post(nil, "ping")
    assert_response :not_found
  end

  test "a tool's answer is fenced as data, with a boundary that is new each time" do
    mcp_post(@token, "tools/call", { name: "admin_summary", arguments: {} })
    text = response.parsed_body.dig("result", "content", 0, "text")
    assert text.start_with?(AdminMcp::Tool::FENCE_NOTE)
    boundary = text[/=== DATA (\h+) ===/, 1]
    assert_match(/=== END DATA #{boundary} ===\z/, text)
    mcp_post(@token, "tools/call", { name: "admin_summary", arguments: {} })
    assert_not_equal boundary, response.parsed_body.dig("result", "content", 0, "text")[/=== DATA (\h+) ===/, 1]
  end

  test "query_sql's audit row holds the SHA-256 of the SQL and no text" do
    sql = "select 1 as secret_looking_column"
    mcp_tool(@token, "query_sql", { sql: })
    ids = AdminAuditEvent.last.ids
    assert_equal Digest::SHA256.hexdigest(sql), ids["sql_sha256"]
    assert_equal sql.length, ids["sql_length"]
    assert_not_includes ids.to_s, "secret_looking_column"
  end

  test "audit ids keep only the keys a tool declares, and cap a list" do
    declared = %w[ship_id]
    ids = AdminMcp::Tool.audit_ids({ ship_id: 4, user_id: 9, ids: (1..80).to_a, note_ids: "x" }, allowed: declared)
    assert_equal({ "ship_id" => 4 }, ids)
    capped = AdminMcp::Tool.audit_ids({ user_ids: (1..80).to_a })
    assert_equal AdminMcp::Tool::MAX_AUDIT_IDS, capped["user_ids"].size
  end

  test "the audit row is written before the tool runs, with IDs and no text" do
    ids_seen = nil
    replacing(AdminMcp::Tools::People::GetPerson, :run, ->(_args, _caller) { ids_seen = AdminAuditEvent.last.ids; {} }) do
      mcp_tool(@token, "get_person", { user_id: users(:ana).id })
    end
    assert_equal({ "user_id" => users(:ana).id }, ids_seen)

    event = AdminAuditEvent.last
    assert_equal "get_person", event.tool
    assert_equal users(:orpheus), event.user
    assert_equal @record, event.admin_token

    mcp_tool(@token, "find_people", { query: "ana@hackclub.com" })
    assert_equal({}, AdminAuditEvent.last.ids)
    assert_not_includes AdminAuditEvent.pluck(:ids, :tool).flatten.to_s, "ana@hackclub.com"
  end

  test "a tool whose audit row fails does not run" do
    ran = false
    replacing(AdminMcp::Tools::Overview::AdminSummary, :run, ->(_args, _caller) { ran = true }) do
      replacing(AdminAuditEvent, :create!, ->(**) { raise ActiveRecord::StatementInvalid, "down" }) do
        assert_match(/audit row could not be written/, mcp_tool(@token, "admin_summary"))
      end
    end
    assert mcp_error?
    assert_not ran
  end

  test "a token gets 240 requests a minute" do
    freeze_time do
      store = ActiveSupport::Cache::MemoryStore.new
      replacing(Rails, :cache, -> { store }) do
        240.times { mcp_post(@token, "ping") }
        assert_response :success
        mcp_post(@token, "ping")
        assert_response :too_many_requests
        assert_equal "60", response.headers["Retry-After"]

        other, = mcp_token_for(name: "another")
        mcp_post(other, "ping")
        assert_response :success, "another token has its own"
      end
    end
  end

  test "the audit log tool reads recent calls" do
    mcp_tool(@token, "admin_summary")
    log = mcp_tool(@token, "audit_log", { tool: "admin_summary" })
    assert_equal 1, log["total"]
    assert_equal({ "tool" => "admin_summary", "ids" => {}, "user_id" => users(:orpheus).id, "admin" => "Orpheus", "token" => "test" },
                 log["events"].first.slice("tool", "ids", "user_id", "admin", "token"))
  end

  # Reads.

  test "admin_summary shows what's waiting" do
    projects(:ana).create_extension!(reason: "exams")
    summary = mcp_tool(@token, "admin_summary")
    assert_equal({ "orders" => 0, "ships_in_review" => 0, "ships_awaiting_fraud" => 0, "extensions" => 1 }, summary["waiting"])
    assert_equal User.count, summary.dig("totals", "people")
    assert_includes summary["summary"].keys, "signups"
  end

  test "find_people and get_person show what the People page shows" do
    people = mcp_tool(@token, "find_people", { query: "pixelana" })
    assert_equal 1, people["total"]
    ana = people["people"].first
    assert_equal({ "id" => users(:ana).id, "name" => "Ana Lovelace", "email" => "ana@hackclub.com", "slack_display_name" => "pixelana" },
                 ana.slice("id", "name", "email", "slack_display_name"))
    assert_equal "ident!ana", ana["hca_id"]
    assert_equal projects(:ana).id, ana.dig("project", "id")

    assert_equal 2, mcp_tool(@token, "find_people", { limit: 1 })["total"] - 0
    assert_equal 1, mcp_tool(@token, "find_people", { limit: 1 })["people"].size

    person = mcp_tool(@token, "get_person", { user_id: users(:orpheus).id })
    assert_equal true, person["admin"]
    assert_equal [], person["ships"]

    assert_match(/Not found: User/, mcp_tool(@token, "get_person", { user_id: 0 }))
  end

  test "find_people and get_person show the Hackatime ID and trust level, and find_people matches an exact ID" do
    users(:ana).update_columns(hackatime_uid: "424242", hackatime_trust_level: "red")
    ana = mcp_tool(@token, "find_people", { query: "424242" })
    assert_equal [ users(:ana).id ], ana["people"].map { it["id"] }
    assert_equal [ "424242", "red" ], ana["people"].first.values_at("hackatime_uid", "hackatime_trust_level")
    assert_equal 0, mcp_tool(@token, "find_people", { query: "4242" })["total"]
    assert_nil mcp_tool(@token, "get_person", { user_id: users(:orpheus).id })["hackatime_trust_level"]
  end

  test "get_person refresh_trust_level asks Hackatime and returns the fresh level" do
    ana = users(:ana)
    ana.update_columns(hackatime_uid: "424242", hackatime_access_token: "tok", hackatime_trust_level: "green")
    Hackatime.stubbed_trust_levels = { "424242" => "red" }
    assert_equal "green", mcp_tool(@token, "get_person", { user_id: ana.id })["hackatime_trust_level"]
    assert_equal "red", mcp_tool(@token, "get_person", { user_id: ana.id, refresh_trust_level: true })["hackatime_trust_level"]
    assert_equal "red", ana.reload.hackatime_trust_level

    Hackatime.stubbed_trust_levels = { "424242" => :unavailable }
    assert_match(/Could not refresh the trust level/, mcp_tool(@token, "get_person", { user_id: ana.id, refresh_trust_level: true }))
  ensure
    Hackatime.stubbed_trust_levels = {}
  end

  test "find_projects and get_project show what the Projects page shows" do
    projects = mcp_tool(@token, "find_projects", { query: "pong" })
    assert_equal 1, projects["total"]
    assert_equal({ "id" => projects(:ana).id, "title" => "pong", "ship" => "none", "hackatime" => "not linked" },
                 projects["projects"].first.slice("id", "title", "ship", "hackatime"))

    project = mcp_tool(@token, "get_project", { project_id: projects(:ana).id })
    assert_equal "pong", project["idea"]
    assert_equal "ana@hackclub.com", project.dig("user", "email")
    assert_equal [], project["ships"]
    assert_equal Program::DATES.end.to_s, project["deadline"]
    assert_equal [ nil, nil, nil ], project.values_at("hackatime_seen_count", "hackatime_seen_hours", "hackatime_seen_at")

    assert_equal [ false, nil ], projects["projects"].first.values_at("party_queued", "play_url")
    assert_equal [ false, nil ], project.values_at("party_queued", "play_url")
    assert_equal 0, mcp_tool(@token, "find_projects", { party_queued: true })["total"]
    ship = make_ship
    projects(:ana).update_columns(party_queued: true)
    queued = mcp_tool(@token, "find_projects", { party_queued: true })
    assert_equal [ projects(:ana).id ], queued["projects"].map { it["id"] }
    assert_equal [ true, ship.demo_url ], queued["projects"].first.values_at("party_queued", "play_url")
    assert_equal 0, mcp_tool(@token, "find_projects", { party_queued: false, query: "pong" })["total"]
    assert_equal [ true, ship.demo_url ], mcp_tool(@token, "get_project", { project_id: projects(:ana).id }).values_at("party_queued", "play_url")
    projects(:ana).update_columns(party_queued: false)

    projects(:ana).update_columns(hackatime_seen_count: 2, hackatime_seen_seconds: 5400, hackatime_seen_at: Time.utc(2026, 10, 24, 9))
    project = mcp_tool(@token, "get_project", { project_id: projects(:ana).id })
    assert_equal [ 2, 1.5 ], project.values_at("hackatime_seen_count", "hackatime_seen_hours")
    assert project["hackatime_seen_at"].present?
  end

  test "find_ships and get_ship show what the review page shows, and nothing is asked of the network but GitHub" do
    ship = make_ship
    Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 200, headers: {}, body: "[]") }

    ships = mcp_tool(@token, "find_ships")
    assert_equal 1, ships["total"]
    assert_equal({ "id" => ship.id, "title" => "Pong", "status" => "in_review", "status_label" => "In review", "hours" => 7.5 },
                 ships["ships"].first.slice("id", "title", "status", "status_label", "hours"))
    assert_equal 0, mcp_tool(@token, "find_ships", { status: "decided" })["total"]
    assert_equal 1, mcp_tool(@token, "find_ships", { status: "all", query: "pixelana" })["total"]

    full = mcp_tool(@token, "get_ship", { ship_id: ship.id })
    assert_equal "ana@hackclub.com", full.dig("user", "email")
    assert_equal "Added a second ball.", full["changes_made"]
    assert_equal 7.5, full["hours_counted"]
    assert_equal "launch", full["hours_start_source"], "D-065"
    assert_equal Program::STARTS_AT.as_json, full["hours_start"]
    assert_equal 7.5, full.dig("limits", "most_to_approve")
    assert_equal false, full.dig("limits", "ai_known")
    assert_equal "ok", full.dig("commits", "status")
    assert_equal "not_configured", full.dig("earlier_ship", "status")
    assert_nil full["review_feedback"]
    assert_equal({}, full["review_checklist"])
    assert_kind_of Hash, full["checklist_defaults"]
    # D-063: the evidence panels, each with its own status when a service can't say.
    assert_match(/haven't linked Hackatime/, full.dig("evidence", "hackatime_projects", "problem"))
    assert_equal "error", full.dig("evidence", "repo", "status"), "the stubbed answer isn't a repository"
    assert_equal "ana@hackclub.com", full.dig("evidence", "participant", "email")
    assert_equal "https://telescreen.hackclub.com/workbench/lapse", full.dig("evidence", "links", "lapse_review"), "no Hackatime id, so the bare workbench"
    assert_equal "https://telescreen.hackclub.com/workbench/hackatime/overview", full.dig("evidence", "links", "telescreen")
  end

  test "get_ship returns the feedback, judgement and frozen checklist of a decided ship" do
    ship = make_ship
    Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 200, headers: {}, body: "[]") }
    ship.update!(review_checklist: { "runs" => true })
    assert ship.decide!("changes_needed", by: users(:orpheus), feedback: "Add a README.", judgement: "Thin changes.")

    full = mcp_tool(@token, "get_ship", { ship_id: ship.id })
    assert_equal "Add a README.", full["review_feedback"]
    assert_equal "Thin changes.", full["review_judgement"]
    assert_equal true, full.dig("review_checklist", "runs")
    assert_nil full["checklist_defaults"]
  end

  # D-111: the sync won't send a deflation with a part that has no reason, but get_ship still answers, and says which part.
  test "get_ship answers for an approved ship whose cut has a part with no reason, and names that part (D-111)" do
    ship = make_ship
    ship.update_columns(hours: 10, ai_coding_seconds: 3 * 3600, art_seconds: 0)
    users(:ana).streak_activities.update_all(coded_seconds: 10 * 3600)
    Ship::EarlierShip.token = "pat-test"
    Web.adapter = ->(_method, url, _headers) { Web::Response.new(status: 200, headers: {}, body: URI(url).host == "api.github.com" ? "[]" : { records: [] }.to_json) }
    limits_say = ship.limits(10).reason
    ship.update_columns(approved_columns(5, claimed_hours: 10, review_coding_hours: 5, review_art_hours: 0, deflation_reason: limits_say,
                                         decided_by_id: users(:orpheus).id, decided_at: Time.current))

    full = mcp_tool(@token, "get_ship", { ship_id: ship.id })
    assert_equal "the reviewer's cut of 3 hrs has no reason", full["deflation_problem"]
    assert_not full["justifications"].key?("Justification - Deflation Justification"), "left out, not drawn from part of it"

    ship.update_columns(deflation_reason: "#{limits_say} A menu was cut.")
    full = mcp_tool(@token, "get_ship", { ship_id: ship.id })
    assert_nil full["deflation_problem"]
    assert_match "The reviewer's reason: A menu was cut.", full["justifications"]["Justification - Deflation Justification"]
  ensure
    Ship::EarlierShip.token = nil
  end

  test "save_review_draft merges any subset into the draft, decides nothing, tells nobody and is logged (D-135)" do
    ship = make_ship
    ship.update_columns(art_seconds: 3600, lapse_seconds: 3600)
    stats = [ ship.status, ship.review_hours, ship.reviewer_id, ship.lapse_coding_hours ]

    assert_no_enqueued_jobs only: SlackMessageJob do
      first = mcp_tool(@token, "save_review_draft", { ship_id: ship.id, lapse_coding_hours: 4.15, coding_hours: 5, technical_features: "A second ball." })
      assert_equal true, first["saved"]
      assert_equal({ "lapse_coding_hours" => "4.15", "coding_hours" => "5", "technical_features" => "A second ball." }, first["draft"])

      second = mcp_tool(@token, "save_review_draft", { ship_id: ship.id, ai_coding_hours: 1.5, ai_reason: "Pasted dump", judgement: "Fine.", coding_hours: 4.5, decision: "approved", bogus: "x" })
      assert_equal %w[ai_coding_hours ai_reason coding_hours decision judgement lapse_coding_hours technical_features], second["draft"].keys.sort
      assert_equal "4.5", second["draft"]["coding_hours"]
      assert_equal "A second ball.", second["draft"]["technical_features"]
      shown = mcp_tool(@token, "get_ship", { ship_id: ship.id })
      assert_equal second["draft"], shown["review_draft"]
      assert_equal "Orpheus", shown["review_draft_updated_by"]

      cleared = mcp_tool(@token, "save_review_draft", { ship_id: ship.id, judgement: "" })
      assert_equal "", cleared["draft"]["judgement"]
    end

    ship.reload
    assert_equal stats, [ ship.status, ship.review_hours, ship.reviewer_id, ship.lapse_coding_hours ], "a draft decides nothing and sets no limit"
    assert_equal users(:orpheus), ship.review_draft_updated_by
    assert_equal 3, AdminAuditEvent.where(tool: "save_review_draft").count # get_ship is logged under its own name
    assert_equal({ "ship_id" => ship.id }, AdminAuditEvent.where(tool: "save_review_draft").last.ids)
  end

  test "save_review_draft refuses a ship that is decided, or the admin's own" do
    ship = make_ship
    ship.update_columns(status: "rejected")
    refused = mcp_tool(@token, "save_review_draft", { ship_id: ship.id, judgement: "x" })
    assert_equal false, refused["saved"]
    assert_empty ship.reload.review_draft

    ship.update_columns(status: "in_review")
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0ANA" ] # Ana is an admin now, but this ship is hers
    ana_token, = mcp_token_for(users(:ana))
    assert_match(/judges your own ship/, mcp_tool(ana_token, "save_review_draft", { ship_id: ship.id, judgement: "x" }))
    assert mcp_error?
    assert_empty ship.reload.review_draft
  end

  test "set_lapse_coding and set_reviewer_ai set what the limits read at once, keep the draft in step, log and tell nobody (D-136)" do
    ship = make_ship
    ship.update_columns(art_seconds: 7200, lapse_seconds: 7200, ai_coding_seconds: 0)

    assert_no_enqueued_jobs only: SlackMessageJob do
      refused = mcp_tool(@token, "set_lapse_coding", { ship_id: ship.id, lapse_coding_hours: 5 })
      assert_equal false, refused["saved"]
      assert_match(/Lapse time is/, refused["message"])

      set = mcp_tool(@token, "set_lapse_coding", { ship_id: ship.id, lapse_coding_hours: 1.25 })
      assert_equal true, set["saved"], set["message"]
      assert_equal BigDecimal("1.25"), ship.reload.lapse_coding_hours
      assert_equal "1.25", ship.review_draft["lapse_coding_hours"]
      assert_equal BigDecimal("1.25"), Ship.find(ship.id).limits.lapse_coding

      needs_reason = mcp_tool(@token, "set_reviewer_ai", { ship_id: ship.id, ai_coding_hours: 1.5 })
      assert_equal false, needs_reason["saved"]
      assert_match(/Say what looked AI-generated/, needs_reason["message"])
      assert_nil ship.reload.reviewer_ai_coding_hours

      ai = mcp_tool(@token, "set_reviewer_ai", { ship_id: ship.id, ai_coding_hours: 1.5, ai_reason: "Pasted dump" })
      assert_equal true, ai["saved"], ai["message"]
      ship.reload
      assert_equal [ BigDecimal("1.5"), "Pasted dump" ], [ ship.reviewer_ai_coding_hours, ship.reviewer_ai_reason ]
      assert_equal [ "1.5", "Pasted dump" ], ship.review_draft.values_at("ai_coding_hours", "ai_reason")
      assert_equal BigDecimal("1.5"), Ship.find(ship.id).limits.reviewer_ai

      cleared = mcp_tool(@token, "set_reviewer_ai", { ship_id: ship.id })
      assert_equal true, cleared["saved"]
      assert_nil ship.reload.reviewer_ai_coding_hours
    end

    assert_equal "in_review", ship.status
    assert_nil ship.reviewer_id
    assert_equal 3, AdminAuditEvent.where(tool: "set_reviewer_ai").count
    assert_equal({ "ship_id" => ship.id }, AdminAuditEvent.where(tool: "set_lapse_coding").last.ids)
  end

  test "set_checklist_item ticks and unticks, and refuses a key the page does not have (D-136)" do
    ship = make_ship
    assert_no_enqueued_jobs only: SlackMessageJob do
      assert_equal true, mcp_tool(@token, "set_checklist_item", { ship_id: ship.id, key: "runs", checked: true })["saved"]
      assert_equal true, ship.reload.review_checklist["runs"]
      mcp_tool(@token, "set_checklist_item", { ship_id: ship.id, key: "runs", checked: false })
      assert_equal false, ship.reload.review_checklist["runs"]
      mcp_tool(@token, "set_checklist_item", { ship_id: ship.id, key: "bogus", checked: true })
      assert mcp_error?
    end
    assert_not ship.reload.review_checklist.key?("bogus")
    assert_equal "in_review", ship.status
    assert_equal 2, AdminAuditEvent.where(tool: "set_checklist_item").count # the bogus key never passes the schema
  end

  test "set_checklist_item takes real_name, which get_ship shows with the names, and it works on an approved ship (D-143)" do
    ship = make_ship
    full = mcp_tool(@token, "get_ship", { ship_id: ship.id })
    assert_equal({ "first_name" => ship.project.user.first_name, "last_name" => AirtableFields.names(ship.project.user).last, "concern" => nil, "ticked" => false, "ysws_eligible" => true }, full["real_name"].slice("first_name", "last_name", "concern", "ticked", "ysws_eligible"))
    assert_equal [ false, [], nil ], full["real_name"].values_at("tick_is_stale", "ticked_for", "ticked_by")
    assert_equal false, full.dig("checklist_defaults", "real_name", "ticked"), "the app never ticks it"
    assert_equal true, mcp_tool(@token, "set_checklist_item", { ship_id: ship.id, key: "real_name", checked: true })["saved"]
    assert_equal true, ship.reload.real_name_checked?

    ship.update_columns(approved_columns(ship.hours))
    mcp_tool(@token, "set_checklist_item", { ship_id: ship.id, key: "runs", checked: true })
    assert mcp_error?, "other items lock at the verdict"
    mcp_tool(@token, "set_checklist_item", { ship_id: ship.id, key: "real_name", checked: false })
    assert_not mcp_error?
    assert_equal false, ship.reload.review_checklist["real_name"]
  end

  test "set_hours_start moves and clears the override through the model, and logs the project (D-136)" do
    ship = make_ship
    project = ship.project
    start = (Program::STARTS_AT + 1.day).utc.strftime("%Y-%m-%dT%H:%M")
    travel_to(Program::STARTS_AT + 3.days) do
      assert_no_enqueued_jobs only: SlackMessageJob do
        too_early = mcp_tool(@token, "set_hours_start", { ship_id: ship.id, hours_start: "2000-01-01T00:00" })
        assert_equal false, too_early["saved"]
        assert_match(/before Save Point began/, too_early["message"])

        assert_equal true, mcp_tool(@token, "set_hours_start", { ship_id: ship.id, hours_start: start })["saved"]
        assert_equal Time.find_zone!("UTC").parse(start), project.reload.hours_start_override

        mcp_tool(@token, "set_hours_start", { ship_id: ship.id, hours_start: "nonsense" })
        assert mcp_error?

        assert_equal true, mcp_tool(@token, "set_hours_start", { ship_id: ship.id, clear: true })["saved"]
        assert_nil project.reload.hours_start_override
      end
    end
    assert_includes AdminAuditEvent.where(tool: "set_hours_start").map(&:ids), { "ship_id" => ship.id, "project_id" => project.id }
  end

  test "set_ship_until sets and clears a private ship window, logs the project, and sends nothing (D-155)" do
    project = projects(:ana)
    window = "2026-11-06T04:00"
    assert_no_enqueued_jobs only: SlackMessageJob do
      done = mcp_tool(@token, "set_ship_until", { user_id: project.user_id, ship_until: window })
      assert_equal project.id, done["project_id"]
      assert_equal Time.utc(2026, 11, 6, 4), project.reload.ship_until
      assert_equal Time.utc(2026, 11, 6, 4), project.ship_closes_at

      mcp_tool(@token, "set_ship_until", { project_id: project.id, ship_until: "nonsense" })
      assert mcp_error?
      assert_equal Time.utc(2026, 11, 6, 4), project.reload.ship_until

      mcp_tool(@token, "set_ship_until", { project_id: project.id, ship_until: nil })
      assert_nil project.reload.ship_until
    end
    assert_includes AdminAuditEvent.where(tool: "set_ship_until").map(&:ids), { "user_id" => project.user_id, "project_id" => project.id }
  end

  test "credit_shop_hours adds to what can be spent, validates, caps, and logs old and new (D-157)" do
    project = projects(:ana)
    before_approved = project.hours_approved
    before_spend = project.hours_to_spend
    assert_no_enqueued_jobs only: SlackMessageJob do
      done = mcp_tool(@token, "credit_shop_hours", { user_id: project.user_id, hours: 0.04, reason: "Only 0.04 short" })
      assert_equal 0.04, done["shop_hours_credit"]
      assert_in_delta before_spend + 0.04, project.reload.hours_to_spend, 0.001
      assert_equal before_approved, project.hours_approved
      assert_equal "Only 0.04 short", project.shop_hours_credit_reason
      assert_equal @record.user.id, project.shop_hours_credit_by_id

      [ { hours: 0, reason: "x" }, { hours: -1, reason: "x" }, { hours: 2.5, reason: "x" }, { hours: 1, reason: " " } ].each do |bad|
        mcp_tool(@token, "credit_shop_hours", { project_id: project.id }.merge(bad))
        assert mcp_error?, bad.inspect
      end
      assert_equal 0.04, project.reload.shop_hours_credit.to_f

      mcp_tool(@token, "credit_shop_hours", { project_id: project.id, hours: 2, reason: "a" })
      mcp_tool(@token, "credit_shop_hours", { project_id: project.id, hours: 2, reason: "b" })
      mcp_tool(@token, "credit_shop_hours", { project_id: project.id, hours: 2, reason: "c" })
      assert mcp_error?
      assert_equal 4.04, project.reload.shop_hours_credit.to_f
    end
    assert_includes AdminAuditEvent.where(tool: "credit_shop_hours").map(&:ids),
                    { "user_id" => project.user_id, "project_id" => project.id, "old_credit" => 0.0, "new_credit" => 0.04 }
  end

  test "set_shop_until sets and clears a per-person shop close, needs a reason, logs old and new, sends nothing (D-158)" do
    project = projects(:ana)
    later = "2026-11-10T21:00"
    assert_no_enqueued_jobs only: SlackMessageJob do
      mcp_tool(@token, "set_shop_until", { project_id: project.id, until: later })
      assert mcp_error?, "a reason is needed"
      done = mcp_tool(@token, "set_shop_until", { user_id: project.user_id, until: later, reason: "Approved late" })
      assert_equal project.id, done["project_id"]
      assert_equal Time.utc(2026, 11, 10, 21), project.reload.shop_closes_at
      assert_equal "Approved late", project.shop_until_reason

      mcp_tool(@token, "set_shop_until", { project_id: project.id, until: "nonsense", reason: "x" })
      assert mcp_error?
      mcp_tool(@token, "set_shop_until", { project_id: project.id, until: "2026-11-01T00:00", reason: "x" })
      assert_equal Program::SHOP_CLOSES_AT, project.reload.shop_closes_at, "an earlier time never shortens the public close"

      mcp_tool(@token, "set_shop_until", { project_id: project.id, until: nil })
      assert_nil project.reload.shop_until
    end
    assert_includes AdminAuditEvent.where(tool: "set_shop_until").map(&:ids),
                    { "user_id" => project.user_id, "project_id" => project.id, "old_shop_until" => nil, "new_shop_until" => later }
  end

  test "send_verdict_dm sends the verdict DM once, returns its text, and can leave the note out (D-139)" do
    sent = []
    dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil, allow_banned: false| sent << text; Struct.new(:channel, :ts).new("D0ANA", "1.0") }
    ship = make_ship
    user = ship.project.user
    user.update!(timezone: "America/New_York", slack_id: "U0ANA")
    travel_to(Program::ENDS_AT - 6.hours) do
      ship.update_columns(status: "changes_needed", reviewed_at: Time.current, decided_at: Time.current, review_feedback: "The art cap ruling.")

      done = mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id })
      assert_equal true, done["sent"]
      assert_equal sent.sole, done["text"]
      assert_includes done["text"], "> The art cap ruling."
      assert_equal "Tue Nov 3, 5:59 pm", done["deadline"]
      assert done["sent_at"]
      assert_includes AdminAuditEvent.where(tool: "send_verdict_dm").map(&:ids), { "ship_id" => ship.id }

      mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id })
      assert mcp_error?, "once only"
      assert_equal 1, sent.size
    end
  ensure
    SlackBot.define_singleton_method(:dm, dm)
  end

  test "send_verdict_dm with include_note false carries the deadline only, and refuses other statuses" do
    sent = []
    dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil, allow_banned: false| sent << text; Struct.new(:channel, :ts).new("D0ANA", "1.0") }
    ship = make_ship
    ship.project.user.update!(timezone: "America/New_York", slack_id: "U0ANA")
    travel_to(Program::ENDS_AT - 6.hours) do
      mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id })
      assert mcp_error?, "an in-review ship has no verdict DM"

      ship.update_columns(status: "changes_needed", reviewed_at: Time.current, decided_at: Time.current, review_feedback: "The art cap ruling.")
      done = mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id, include_note: false })
      assert_equal true, done["sent"]
      assert_includes done["text"], "you have until Tue Nov 3, 5:59 pm"
      assert_not_includes done["text"], "art cap"
      assert_not_includes done["text"], "your reviewer left you a note"
    end
  ensure
    SlackBot.define_singleton_method(:dm, dm)
  end

  test "send_verdict_dm restart_window makes the deadline 24 hours from now (D-140)" do
    sent = []
    dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil, allow_banned: false| sent << text; Struct.new(:channel, :ts).new("D0ANA", "1.0") }
    ship = make_ship
    ship.project.user.update!(timezone: "America/New_York", slack_id: "U0ANA")
    travel_to(Program::ENDS_AT - 6.hours) do
      ship.update_columns(status: "changes_needed", reviewed_at: Time.current - 20.hours, decided_at: Time.current - 20.hours, review_feedback: "Fix it.")
      done = mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id, restart_window: true })
      assert_equal true, done["sent"]
      assert_in_delta Time.current, ship.reload.reviewed_at, 1.second
      assert_equal (Time.current + 24.hours).in_time_zone("America/New_York").strftime("%a %b %-d, %-l:%M %P"), done["deadline"]
      assert_includes AdminAuditEvent.where(tool: "send_verdict_dm").map(&:ids), { "ship_id" => ship.id, "project_id" => ship.project_id }
    end
  ensure
    SlackBot.define_singleton_method(:dm, dm)
  end

  test "send_verdict_dm restart_window refuses an approved ship" do
    ship = make_ship
    ship.update_columns(status: "approved", approved_hours: 7.5, review_hours: 7.5, reviewed_at: Time.current - 2.hours, decided_at: Time.current - 2.hours)
    before = ship.reload.reviewed_at
    mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id, restart_window: true })
    assert mcp_error?
    assert_equal before, ship.reload.reviewed_at
  end

  test "send_verdict_dm restart_window leaves reviewed_at alone when the DM was already sent" do
    sent = []
    dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil, allow_banned: false| sent << text; Struct.new(:channel, :ts).new("D0ANA", "1.0") }
    ship = make_ship
    ship.project.user.update!(timezone: "America/New_York", slack_id: "U0ANA")
    travel_to(Program::ENDS_AT - 6.hours) do
      ship.update_columns(status: "changes_needed", reviewed_at: Time.current, decided_at: Time.current, review_feedback: "Fix it.")
      mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id })
      reviewed_at = ship.reload.reviewed_at
      travel 5.hours
      mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id, restart_window: true })
      assert mcp_error?
      assert_equal reviewed_at, ship.reload.reviewed_at
      assert_equal 1, sent.size
    end
  ensure
    SlackBot.define_singleton_method(:dm, dm)
  end

  test "send_verdict_dm without restart_window keeps reviewed_at" do
    sent = []
    dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:, on_error: nil, allow_banned: false| sent << text; Struct.new(:channel, :ts).new("D0ANA", "1.0") }
    ship = make_ship
    ship.project.user.update!(timezone: "America/New_York", slack_id: "U0ANA")
    travel_to(Program::ENDS_AT - 6.hours) do
      at = Time.current - 3.hours
      ship.update_columns(status: "changes_needed", reviewed_at: at, decided_at: at, review_feedback: "Fix it.")
      assert_equal true, mcp_tool(@token, "send_verdict_dm", { ship_id: ship.id })["sent"]
      assert_in_delta at, ship.reload.reviewed_at, 1.second
    end
  ensure
    SlackBot.define_singleton_method(:dm, dm)
  end

  test "edit_snapshot saves a subset through Ship::Snapshot, stamps the edit and refuses a bad field (D-136)" do
    ship = make_ship
    assert_no_enqueued_jobs only: SlackMessageJob do
      done = mcp_tool(@token, "edit_snapshot", { ship_id: ship.id, title: "Pong 2", demo_url: "https://example.com/pong2" })
      assert_equal true, done["saved"]
      ship.reload
      assert_equal [ "Pong 2", "https://example.com/pong2", "Added a second ball." ], [ ship.title, ship.demo_url, ship.changes_made ]
      assert_equal users(:orpheus), ship.snapshot_edited_by

      bad = mcp_tool(@token, "edit_snapshot", { ship_id: ship.id, repo_url: "javascript:alert(1)" })
      assert_equal false, bad["saved"]
      assert bad["errors"].key?("repo_url")
      assert_equal "https://github.com/ana/pong", ship.reload.repo_url

      assert_equal "Nothing changed.", mcp_tool(@token, "edit_snapshot", { ship_id: ship.id, title: "Pong 2" })["message"]
    end
    assert_equal 1, AdminAuditEvent.where(tool: "edit_ship").count
    assert_equal 3, AdminAuditEvent.where(tool: "edit_snapshot").count
  end

  test "edit_review_text fixes the text of an approved ship before Unified, marks it unsynced and logs old and new (D-150)" do
    ship = make_ship
    ship.update_columns(status: "approved", technical_features: "Old features.", review_judgement: "Old view.", review_hours: 7.5, approved_hours: 7.5, decided_at: Time.current, synced_at: Time.current)
    done = mcp_tool(@token, "edit_review_text", { ship_id: ship.id, technical_features: "New features.", judgement: "New view." })
    assert_equal true, done["saved"]
    ship.reload
    assert_equal [ "New features.", "New view.", 7.5, "approved" ], [ ship.technical_features, ship.review_judgement, ship.review_hours, ship.status ]
    assert_nil ship.synced_at, "the corrected text goes out with the first send"
    event = AdminAuditEvent.where(tool: "edit_review_text").order(:id).last
    assert_equal({ "technical_features" => [ "Old features.", "New features." ], "review_judgement" => [ "Old view.", "New view." ] }, event.ids["changes"])

    assert_equal "Nothing changed.", mcp_tool(@token, "edit_review_text", { ship_id: ship.id, technical_features: "New features." })["message"]
    assert_match(/Say which technical features/, mcp_tool(@token, "edit_review_text", { ship_id: ship.id, technical_features: "" })["message"])
    assert_match(/Only the review text can change/, mcp_tool(@token, "edit_review_text", { ship_id: ship.id, coding_hours: 2 }))
    assert_equal "New features.", ship.reload.technical_features
  end

  test "edit_review_text refuses a ship already in Unified and a ship still in review (D-150)" do
    ship = make_ship
    ship.update_columns(status: "approved", technical_features: "Old features.", in_unified: true, review_hours: 7.5, approved_hours: 7.5)
    result = mcp_tool(@token, "edit_review_text", { ship_id: ship.id, technical_features: "New" })
    assert_equal false, result["saved"]
    assert_equal "Not saved: #{Ship::IN_UNIFIED_MESSAGE}", result["message"]
    assert_equal "Old features.", ship.reload.technical_features

    ship.update_columns(status: "in_review", in_unified: false)
    assert_equal false, mcp_tool(@token, "edit_review_text", { ship_id: ship.id, technical_features: "New" })["saved"]
    assert_equal "Old features.", ship.reload.technical_features
    # a ship in review still takes a draft, as before
    assert_equal true, mcp_tool(@token, "save_review_draft", { ship_id: ship.id, technical_features: "Drafted" })["saved"]
    ship.update_columns(status: "approved", review_hours: 7.5, approved_hours: 7.5)
    assert_equal false, mcp_tool(@token, "save_review_draft", { ship_id: ship.id, technical_features: "Drafted 2" })["saved"]
  end

  test "the D-136 tools refuse a ship that is not in review, or the admin's own, and change nothing" do
    calls = { "set_lapse_coding" => { lapse_coding_hours: 1 }, "set_reviewer_ai" => { ai_coding_hours: 1, ai_reason: "x" },
              "set_checklist_item" => { key: "runs", checked: true }, "set_hours_start" => { clear: true }, "edit_snapshot" => { title: "Changed title" } }
    ship = make_ship
    ship.update_columns(status: "rejected")
    calls.each do |name, args|
      assert_match(/Only a ship in review/, mcp_tool(@token, name, { ship_id: ship.id, **args }), name)
      assert mcp_error?, name
    end
    assert_equal [ 0.0, nil, {}, "Pong" ], [ ship.reload.lapse_coding_hours, ship.reviewer_ai_coding_hours, ship.review_checklist, ship.title ]

    ship.update_columns(status: "in_review")
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0ANA" ]
    ana_token, = mcp_token_for(users(:ana))
    calls.each do |name, args|
      assert_match(/judges your own ship/, mcp_tool(ana_token, name, { ship_id: ship.id, **args }), name)
      assert mcp_error?, name
    end
    assert_equal [ 0.0, nil, {}, "Pong" ], [ ship.reload.lapse_coding_hours, ship.reviewer_ai_coding_hours, ship.review_checklist, ship.title ]
  end

  test "a verdict clears the draft (D-135)" do
    ship = make_ship
    Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 200, headers: {}, body: "[]") }
    mcp_tool(@token, "save_review_draft", { ship_id: ship.id, judgement: "Looks thin." })
    assert ship.reload.decide!("rejected", by: users(:orpheus), judgement: "Looks thin.")
    assert_equal "rejected", ship.reload.status
    assert_empty ship.review_draft
  end

  # D-136, D-148: no MCP tool presses a verdict. The page does.
  test "no tool gives a verdict: review_ship and fraud_ship are gone, and no tool file calls the verdict methods" do
    mcp_post(@token, "tools/list")
    names = response.parsed_body.dig("result", "tools").map { it["name"] }
    assert_not_includes names, "review_ship"
    assert_not_includes names, "fraud_ship"

    verdicts = /\.(decide!|pass_fraud!|ban_for_fraud!)\b/
    Dir[Rails.root.join("app/mcp/**/*.rb").to_s].each do |file|
      assert_no_match verdicts, File.read(file).lines.reject { it.strip.start_with?("#") }.join, "#{file} presses a verdict"
    end
  end

  test "list_orders shows the address only for the ones to order" do
    waiting = make_order("micro", "waiting")
    ordered = make_order("u2c", "ordered", ordered_by: users(:orpheus))

    orders = mcp_tool(@token, "list_orders")["orders"]
    assert_equal [ waiting.id ], orders.map { it["id"] }
    assert_match(/15 Falls Rd/, orders.first["address"])
    assert_equal "Ana Lovelace", orders.first["recipient"]

    all = mcp_tool(@token, "list_orders", { status: "all" })["orders"]
    assert_equal [ waiting.id, ordered.id ], all.map { it["id"] }
    assert_not all.last.key?("address")
    assert_equal "Orpheus", all.last["ordered_by"]
  end

  test "list_extensions and the numbers tools answer" do
    extension = projects(:ana).create_extension!(reason: "exams")
    assert_equal [ extension.id ], mcp_tool(@token, "list_extensions")["extensions"].map { it["id"] }
    assert_equal 0, mcp_tool(@token, "list_extensions", { status: "decided" })["total"]

    assert_includes mcp_tool(@token, "metrics", { days: 3 }).keys, "nps"
    assert_includes mcp_tool(@token, "nudges").keys, "buckets"
    totals = mcp_tool(@token, "nudges")["totals"]
    assert_equal totals["scored"] - totals["worked"], totals["didnt_work"]
    assert_not_includes totals.keys, "failed", "that was scored minus worked, not delivery failures (cannot_dm is those)"
    users(:orpheus).update!(slack_dm_failed_at: 1.hour.ago, slack_dm_error: "user_disabled")
    nudges = mcp_tool(@token, "nudges")
    assert_equal 1, nudges["cannot_dm"]
    assert_equal [ { "user_id" => users(:orpheus).id, "error" => "user_disabled" } ], nudges["cannot_dm_details"].map { it.slice("user_id", "error") }
    assert_includes mcp_tool(@token, "public_stats").keys, "totals"
  end

  # Writes: the same model methods the admin pages call.

  test "mark_order_ordered orders once, and the bot DMs them" do
    order = make_order("micro", "waiting")
    result = mcp_tool(@token, "mark_order_ordered", { order_id: order.id })
    assert_equal true, result["ordered"]
    assert order.reload.ordered?
    assert_equal users(:orpheus), order.ordered_by
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_match(/Your 8BitDo Micro is ordered/, dm[:args].second)
    assert_equal({ "order_id" => order.id }, AdminAuditEvent.last.ids)

    again = mcp_tool(@token, "mark_order_ordered", { order_id: order.id })
    assert_equal false, again["ordered"]
    assert_equal "That one's been ordered already.", again["message"]
  end

  test "mark_order_ordered sends a sticker order to Theseus first, and can't mark one that wasn't sent" do
    order = make_order("stickers", "waiting", hours: 0)

    ENV.delete("THESEUS_API_KEY")
    refused = mcp_tool(@token, "mark_order_ordered", { order_id: order.id })
    assert_equal false, refused["ordered"]
    assert_equal "Theseus isn't set up: THESEUS_API_KEY is missing", refused["message"]
    assert order.reload.waiting?

    ENV["THESEUS_API_KEY"] = "k"
    Web.adapter = ->(*) { Web::Response.new(status: 201, headers: {}, body: { id: "ltr_abc123" }.to_json) }
    result = mcp_tool(@token, "mark_order_ordered", { order_id: order.id })
    assert_equal true, result["ordered"]
    assert_equal "ltr_abc123", result.dig("order", "theseus_letter_id")
    assert order.reload.ordered?
    assert_equal "ltr_abc123", order.theseus_letter_id
  ensure
    Web.adapter = nil
    ENV.delete("THESEUS_API_KEY")
  end

  test "decide_extension decides once, and the bot DMs them" do
    extension = projects(:ana).create_extension!(reason: "exams")
    result = mcp_tool(@token, "decide_extension", { extension_id: extension.id, decision: "approved" })
    assert_equal true, result["decided"]
    assert extension.reload.approved?
    assert_equal users(:orpheus), extension.decided_by
    assert enqueued_jobs.any? { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }

    again = mcp_tool(@token, "decide_extension", { extension_id: extension.id, decision: "denied" })
    assert_equal false, again["decided"]
    assert extension.reload.approved?
  end

  # The analytics.

  test "describe_schema lists the views and the admins' hashes" do
    create_insights_views
    schema = mcp_tool(@token, "describe_schema")
    assert_equal %w[faq_reads nps_responses nudges orders projects ships site_days streak_activities users visits], schema["views"].map { it["name"] }.sort
    users_view = schema["views"].find { it["name"] == "users" }
    assert_includes users_view["columns"].map { it["name"] }, "slack_hash"
    assert_equal [ Digest::SHA256.hexdigest("U0ORPHEUS") ], schema["admin_slack_hashes"]
  end

  test "query_sql reads every NPS answer (D-118)" do
    create_insights_views
    NpsResponse.create!(user: users(:ana), source: "daily", score: 8, doing_well: "prizes", improve: "speed")
    answer = mcp_tool(@token, "query_sql", { sql: "select score, doing_well, user_id from nps_responses" })
    assert_not mcp_error?, answer.inspect
    assert_equal [ [ 8, "prizes", users(:ana).id ] ], answer["rows"]
  end

  test "query_sql reads an insights view" do
    create_insights_views
    answer = mcp_tool(@token, "query_sql", { sql: "select user_id, hackatime_linked from users order by user_id" })
    assert_not mcp_error?, answer.inspect
    assert_equal %w[user_id hackatime_linked], answer["columns"]
    assert_equal User.count, answer["row_count"]
    assert_equal false, answer["truncated"]

    qualified = mcp_tool(@token, "query_sql", { sql: "with n as (select count(*) c from insights.users) select c from n;" })
    assert_equal [ [ User.count ] ], qualified["rows"]

    capped = mcp_tool(@token, "query_sql", { sql: "select generate_series(1, 1000) as n", max_rows: 3 })
    assert_equal 3, capped["row_count"]
    assert capped["truncated"]

    assert_equal "after the query", ActiveRecord::Base.connection.select_value("select 'after the query'"), "the connection is usable and writable again"
    assert_equal "public", ActiveRecord::Base.connection.select_value("select current_schema()")
  end

  test "query_sql refuses what isn't a read of the insights views" do
    create_insights_views
    {
      "update insights.orders set hours = 0" => /Only one SELECT/,
      "delete from users" => /Only one SELECT/,
      "select 1; select 2" => /one statement/,
      "select 1; drop table users" => /one statement/,
      "select * from public.users" => /Only the insights schema/,
      'select * from "public"."users"' => /Only the insights schema/,
      "select * from information_schema.columns" => /information_schema/,
      "select * from pg_catalog.pg_roles" => /pg_catalog/,
      "select * from pg_user" => /pg_user/,
      "select * from pg_stat_activity" => /pg_stat_activity/,
      "select pg_read_file('/etc/passwd')" => /pg_read_file/,
      "select pg_ls_dir('.')" => /pg_ls_dir/,
      "select current_setting('data_directory')" => /current_setting\(\)/,
      "select set_config('transaction_read_only', 'off', true)" => /set_config\(\)/,
      "select lo_import('/etc/passwd')" => /lo_import\(\)/,
      "select * from dblink('dbname=x', 'select 1') as t(a int)" => /dblink\(\)/,
      "select query_to_xml('select * from public.users', true, true, '')" => /query_to_xml\(\)/,
      "select nextval('x')" => /nextval\(\)/,
      "select U&'\\0070ublic'" => /Unicode escapes/,
      "set search_path = public" => /Only one SELECT/,
      "copy users to stdout" => /Only one SELECT/,
      "explain select 1" => /Only one SELECT/,
      "select * from users -- the rest is hidden\n; drop table users" => /one statement/,
      "select 1 /* unclosed" => /unclosed comment/,
      "" => /Send one SELECT/
    }.each do |sql, message|
      answer = mcp_tool(@token, "query_sql", { sql: })
      assert mcp_error?, "#{sql.inspect} ran: #{answer.inspect}"
      assert_match message, answer, sql
    end
  end

  test "query_sql cannot write even past the text checks" do
    create_insights_views
    assert_match(/data-modifying/, mcp_tool(@token, "query_sql", { sql: "with d as (delete from orders returning order_id) select * from d" }))
    assert_match(/PostgreSQL refused/, mcp_tool(@token, "query_sql", { sql: "select * into insights.copy from users" }))
    assert_equal 0, ActiveRecord::Base.connection.select_value("select count(*) from pg_tables where tablename = 'copy'")
  end

  test "the transaction around a query is read only, and put back after" do
    connection = ActiveRecord::Base.connection
    error = assert_raises(ActiveRecord::StatementInvalid) do
      AdminMcp::Tools::Analytics::QuerySql.read_only(connection) { connection.execute("create temp table mcp_probe (a int)") }
    end
    assert_match(/read-only transaction/, error.message)
    connection.execute("create temp table mcp_probe (a int)")
    assert_equal "off", connection.select_value("show transaction_read_only")
  end

  test "query_sql stops a long query and cuts a long cell" do
    create_insights_views
    long = mcp_tool(@token, "query_sql", { sql: "select repeat('x', 5000) as text" })
    assert_match(/<5000 characters>/, long["rows"].first.first)
    assert_match(/larger than/, mcp_tool(@token, "query_sql", { sql: "select repeat('x', 300000) as text" }))
  end

  test "funnel counts participants through each step, leaving admins out" do
    create_insights_views
    project = projects(:ana)
    users(:ana).update!(hackatime_uid: "1002", hackatime_access_token: "token-heidi")
    project.update_columns(hackatime_projects: [ "pong" ], hackatime_seen_count: 1, hackatime_seen_seconds: 600)
    users(:ana).streak_activities.create!(activity_date: Program::HACKATIME_START, coded_seconds: 5.5 * 3600)
    users(:orpheus).streak_activities.create!(activity_date: Program::HACKATIME_START, coded_seconds: 20 * 3600)

    funnel = mcp_tool(@token, "funnel")
    assert_not mcp_error?, funnel.inspect
    assert_equal 1, funnel["participants"], "Orpheus is an admin"
    counts = funnel["steps"].to_h { [ it["key"], it["count"] ] }
    assert_equal({ "signed_in" => 1, "pledged" => 1, "linked" => 1, "editor_sent" => 1, "set_up" => 1, "first_20" => 1, "past_5h" => 1, "past_10h" => 0,
                   "shipped" => 0, "approved" => 0, "claimed" => 0 }, counts)
    assert_equal [ nil, 100.0 ], funnel["steps"].first(2).map { it["kept_percent"] }
    assert_equal 1, funnel["steps"][7]["lost"]

    projects(:ana).update_columns(hackatime_seen_seconds: 0)
    steps = mcp_tool(@token, "funnel")["steps"].to_h { [ it["key"], it ] }
    assert_equal 0, steps["editor_sent"]["count"], "Hackatime showed no time"
    assert_equal [ 1, 0 ], steps["set_up"].values_at("count", "lost"), "picking is measured against linking, not editor sent time"
  end

  test "the funnel tool answers exactly what ParticipantFunnel counts" do
    create_insights_views
    users(:ana).update!(hackatime_uid: "1002", hackatime_access_token: "token-ana")
    users(:ana).streak_activities.create!(activity_date: Program::HACKATIME_START, coded_seconds: 5.5 * 3600)

    assert_equal ParticipantFunnel.run.to_json, mcp_tool(@token, "funnel").to_json
  end

  private
    def make_ship
      travel_to(Program::STARTS_AT + 2.days) do
        users(:ana).streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 7.5 * 3600)
        projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.", changes_made: "Added a second ball.",
                                     repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", hackatime_projects: [ "pong" ], hours: 7.5,
                                     screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
      end
    end

    def make_order(prize_key, status, **attributes)
      order = projects(:ana).orders.new(prize_key:, hours: 6.5, address: HQ_ADDRESS, status:, **attributes)
      order.save!(validate: false) # as if their approved hours covered it
      give_approved_hours(projects(:ana), 6.5) if prize_key != "stickers"
      give_sticker_reward(users(:ana)) if prize_key == "stickers"
      order
    end
end
