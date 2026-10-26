module AdminMcp::Tools::Audit
  # The log of every tool call, as AdminMcp::Tool writes it before the tool runs.
  class AuditLog < AdminMcp::Tool
    reads "audit_log", "Read the admin log",
          "The admin MCP log, newest first: which admin called which tool with which token, and the record IDs the call named. " \
          "No text and no emails are kept. Answers { total, events }.",
          { tool: { type: "string", description: "Only this tool, such as review_ship." },
            user_id: { type: "integer", description: "Only calls by this admin's user ID." },
            since: { type: "string", description: "At or after, ISO 8601, such as 2026-10-23 or 2026-10-23T17:00:00Z." },
            **AdminMcp::Tool::PAGE }

    def self.run(args, _caller)
      events = AdminAuditEvent.includes(:user, :admin_token).newest
      events = events.where(tool: args[:tool]) if args[:tool].present?
      events = events.where(user_id: args[:user_id]) if args[:user_id]
      events = events.where(created_at: since(args[:since])..) if args[:since].present?
      total, rows = page(events, args)
      { total:, events: rows.map { { id: it.id, at: it.created_at, tool: it.tool, ids: it.ids, user_id: it.user_id, admin: it.user.first_name, token: it.admin_token&.name || "web" } } }
    end

    def self.since(text) = Time.zone.parse(text) || raise(AdminMcp::Refused, "since is not a date: #{text}.")
  end
end
