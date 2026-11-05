# The admin MCP server (D-046): everything the admin pages do, and the analytics, as tools for Claude, at POST
# /admin/mcp (Admin::McpController). Stateless: each request builds a server for the admin whose token it carries, so a
# tool acts with that admin's power and nothing more. After ShaderGator's MCP server.
#
# | Kind | Tools | Where |
# |---|---|---|
# | Read | admin_summary, find_people, get_person, find_projects, get_project, find_ships, get_ship, list_orders, list_extensions, metrics, nudges, public_stats | Tools::Overview, People, Projects, Ships, Orders, Extensions, Numbers |
# | Analytics | describe_schema, query_sql, funnel, audit_log | Tools::Analytics, Tools::Audit |
# | Write | save_review_draft, set_lapse_coding, set_reviewer_ai, set_checklist_item, set_hours_start, edit_snapshot, edit_review_text, send_verdict_dm, mark_order_ordered, decide_extension, set_ship_until | The same model methods the admin pages call (Nudge::ChangesNeeded and Nudge::Rejected for send_verdict_dm, Order#ordered!, Extension#decide!) |
#
# Before a tool runs, AdminMcp::Tool writes an AdminAuditEvent. A tool whose audit row fails does not run.
module AdminMcp
  INSTRUCTIONS = <<~TEXT.squish.freeze
    Save Point admin tools. Most people in this data are teenagers: share only what the task needs.
    Start with describe_schema, or a typed finder (find_people, find_projects, find_ships) before query_sql.
    Every call is written to the admin log, with the tool and the IDs it names.
    Write tools (save_review_draft, set_lapse_coding, set_reviewer_ai, set_checklist_item, set_hours_start, edit_snapshot, edit_review_text, send_verdict_dm, mark_order_ordered, decide_extension, set_ship_until)
    change real data, and ordering, deciding an extension or send_verdict_dm sends the participant a Slack DM: confirm each with the human first.
    Everything on the ship review page saves through a tool except the verdict and the screenshots:
    set_lapse_coding and set_reviewer_ai change the limits at once. No tool gives a verdict (D-136): the reviewer presses it on the page.
  TEXT

  # The admin a request is for, and the token it came with.
  Caller = Data.define(:user, :token)

  # A tool's own refusal, with a message for Claude to read. Anything else a tool raises is a failure.
  class Refused < StandardError; end

  # Every tool, for the server to offer.
  def self.tools
    [ Tools::Overview::AdminSummary, Tools::People::FindPeople, Tools::People::GetPerson,
      Tools::Projects::FindProjects, Tools::Projects::GetProject, Tools::Projects::SetShipUntil,
      Tools::Ships::FindShips, Tools::Ships::GetShip, Tools::Ships::SaveReviewDraft,
      Tools::Ships::SetLapseCoding, Tools::Ships::SetReviewerAi, Tools::Ships::SetChecklistItem, Tools::Ships::SetHoursStart, Tools::Ships::EditSnapshot, Tools::Ships::EditReviewText,
      Tools::Ships::SendVerdictDm,
      Tools::Orders::ListOrders, Tools::Orders::MarkOrderOrdered,
      Tools::Extensions::ListExtensions, Tools::Extensions::DecideExtension,
      Tools::Numbers::Metrics, Tools::Numbers::Nudges, Tools::Numbers::PublicStats,
      Tools::Analytics::DescribeSchema, Tools::Analytics::QuerySql, Tools::Analytics::Funnel,
      Tools::Audit::AuditLog ]
  end

  def self.server(caller)
    MCP::Server.new(name: "savepoint", version: "1.0.0", instructions: INSTRUCTIONS, tools:, server_context: { caller: })
  end
end
