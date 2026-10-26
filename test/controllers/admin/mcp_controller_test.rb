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

    assert_equal %w[admin_summary audit_log decide_extension describe_schema find_people find_projects find_ships fraud_ship funnel get_person get_project get_ship
                    list_extensions list_orders mark_order_ordered metrics nudges public_stats query_sql review_ship], tools.keys.sort
    writes = %w[review_ship fraud_ship mark_order_ordered decide_extension]
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
    assert_equal "unknown", full.dig("evidence", "stardance", "status")
    assert_equal "ana@hackclub.com", full.dig("evidence", "participant", "email")
    assert_equal "https://telescreen.hackclub.com/workbench/lapse", full.dig("evidence", "links", "lapse_review")
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

  test "review_ship approves with the limits, or says what's missing, and sends back" do
    ship = make_ship

    missing = mcp_tool(@token, "review_ship", { ship_id: ship.id, decision: "approved" })
    assert_equal false, missing["decided"]
    assert_match(/Name the specific technical features/, missing["message"])
    assert ship.reload.in_review?

    deflated = mcp_tool(@token, "review_ship", { ship_id: ship.id, decision: "approved", coding_hours: 6, technical_features: "A second ball." })
    assert_equal false, deflated["decided"]
    assert_match(/Say why you approve fewer hours/, deflated["message"])

    done = mcp_tool(@token, "review_ship", { ship_id: ship.id, decision: "approved", coding_hours: 6, technical_features: "A second ball.",
                                              deflation_reason: "A menu was cut." })
    assert_equal true, done["decided"]
    assert ship.reload.awaiting_fraud?, "approved goes to the fraud check"
    assert_equal 6, ship.review_hours
    assert_nil ship.approved_hours
    assert_equal users(:orpheus), ship.reviewer
    assert_equal "awaiting_fraud", done.dig("ship", "status")
    assert_equal({ "ship_id" => ship.id }, AdminAuditEvent.last.ids)

    again = mcp_tool(@token, "review_ship", { ship_id: ship.id, decision: "rejected" })
    assert_equal false, again["decided"]
    assert_equal "That one's been decided already.", again["message"]
    assert ship.reload.awaiting_fraud?
  end

  test "fraud_ship passes, deducts, bans or sends back a ship waiting for its fraud check" do
    ship = make_ship
    refused = mcp_tool(@token, "fraud_ship", { ship_id: ship.id, verdict: "pass" })
    assert_equal false, refused["decided"]
    assert_equal "That one isn't waiting for its fraud check.", refused["message"]

    ship.decide!("approved", by: users(:ana), technical_features: "A second ball.")
    assert_equal false, mcp_tool(@token, "fraud_ship", { ship_id: ship.id, verdict: "deduct", deduct_hours: 1 })["decided"]
    assert_equal false, mcp_tool(@token, "fraud_ship", { ship_id: ship.id, verdict: "send_back" })["decided"]
    assert_equal false, mcp_tool(@token, "fraud_ship", { ship_id: ship.id, verdict: "ban" })["decided"]
    assert ship.reload.awaiting_fraud?

    sent = mcp_tool(@token, "fraud_ship", { ship_id: ship.id, verdict: "send_back", reason: "Hours look high." })
    assert_equal true, sent["decided"]
    assert ship.reload.in_review?

    ship.decide!("approved", by: users(:ana), technical_features: "A second ball.")
    done = mcp_tool(@token, "fraud_ship", { ship_id: ship.id, verdict: "deduct", deduct_hours: 1.5, notes: "AFK." })
    assert_equal true, done["decided"]
    assert ship.reload.approved?
    assert_equal BigDecimal("6"), ship.approved_hours
    assert_equal users(:orpheus), ship.decided_by

    other = projects(:ana).ships.create!(ship.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 3,
                                         screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true))
    other.decide!("approved", by: users(:ana), technical_features: "A second ball.")
    assert_equal true, mcp_tool(@token, "fraud_ship", { ship_id: other.id, verdict: "ban", notes: "Same repo as another account." })["decided"]
    assert other.reload.rejected?
    assert users(:ana).reload.banned?

    mcp_post(@token, "tools/call", { name: "fraud_ship", arguments: { ship_id: ship.id, verdict: "maybe" } })
    assert response.parsed_body.dig("result", "isError") || response.parsed_body["error"]
  end

  test "review_ship and fraud_ship refuse your own ship and one another admin holds" do
    ship = make_ship
    Claim.acquire(ship, "review", users(:ana))
    held = mcp_tool(@token, "review_ship", { ship_id: ship.id, decision: "changes_needed", feedback: "Add a README." })
    assert mcp_error?
    assert_match(/another admin|holds|open/i, held)
    assert ship.reload.in_review?

    Claim.where(ship:).delete_all
    ship = projects(:orpheus).ships.create!(ship.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 3,
                                            screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true))
    own = mcp_tool(@token, "review_ship", { ship_id: ship.id, decision: "changes_needed", feedback: "Add a README." })
    assert mcp_error?
    assert_match(/your own/i, own)
    assert ship.reload.in_review?
  end

  test "review_ship sends a ship back as changes needed" do
    ship = make_ship
    refused = mcp_tool(@token, "review_ship", { ship_id: ship.id, decision: "changes_needed" })
    assert_equal false, refused["decided"]
    assert_match(/Tell the participant what to change/, refused["message"])
    assert_equal true, mcp_tool(@token, "review_ship", { ship_id: ship.id, decision: "changes_needed", feedback: "Add a README." })["decided"]
    assert ship.reload.changes_needed?
    assert_equal "Add a README.", ship.review_feedback
    assert_equal "Changes needed", mcp_tool(@token, "find_ships", { status: "changes_needed" })["ships"].first["status_label"]
  end

  test "review_ship refuses a decision that isn't one" do
    ship = make_ship
    mcp_post(@token, "tools/call", { name: "review_ship", arguments: { ship_id: ship.id, decision: "maybe" } })
    assert response.parsed_body.dig("result", "isError") || response.parsed_body["error"]
    assert ship.reload.in_review?
  end

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
    assert_equal %w[nudges orders projects ships site_days streak_activities users visits], schema["views"].map { it["name"] }.sort
    users_view = schema["views"].find { it["name"] == "users" }
    assert_includes users_view["columns"].map { it["name"] }, "slack_hash"
    assert_equal [ Digest::SHA256.hexdigest("U0ORPHEUS") ], schema["admin_slack_hashes"]
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
      order
    end
end
