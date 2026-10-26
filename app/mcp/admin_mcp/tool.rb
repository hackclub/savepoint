# What every admin MCP tool shares. A tool declares itself with `reads` or `writes`, names its arguments in the input
# schema, and implements `run(args, caller)`, which returns what Claude should see (a Hash or Array, sent as JSON).
# `call` writes the audit row first, then runs it, and turns a refusal or a missing record into a message.
class AdminMcp::Tool < MCP::Tool
  CONFIRM = "Changes real data: confirm with the human first. ".freeze
  # The most rows a finder sends in one answer.
  MAX_LIMIT = 200
  DEFAULT_LIMIT = 50

  PAGE = {
    limit: { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Rows per page. Default #{DEFAULT_LIMIT}, at most #{MAX_LIMIT}." },
    offset: { type: "integer", minimum: 0, description: "Rows to skip, for the next page." }
  }.freeze

  class << self
    def reads(name, title, description, properties = {}, required: [])
      declare(name, title, description, properties, required, write: false)
    end

    # A tool that changes data. Its description tells Claude to confirm with the human first.
    def writes(name, title, description, properties = {}, required: [])
      declare(name, title, "#{CONFIRM}#{description}", properties, required, write: true)
    end

    # The arguments' record IDs, for the audit row: any `..._id` or `..._ids` that's a whole number or a list of them.
    # Never any text, so nothing a participant wrote reaches the log.
    def audit_ids(args)
      args.each_with_object({}) do |(key, value), ids|
        next unless key.to_s.match?(/(\A|_)ids?\z/)

        ids[key.to_s] = value if value.is_a?(Integer) || (value.is_a?(Array) && value.all?(Integer))
      end
    end

    def call(server_context:, **args)
      caller = server_context[:caller]
      begin
        AdminAuditEvent.create!(user: caller.user, admin_token: caller.token, tool: tool_name, ids: audit_ids(args))
      rescue StandardError
        return failure("The audit row could not be written, so the tool did not run.")
      end

      success(run(args, caller))
    rescue AdminMcp::Refused => error
      failure(error.message)
    rescue ActiveRecord::RecordNotFound => error
      failure("Not found: #{error.model} #{error.id}.")
    rescue ActiveRecord::RecordInvalid => error
      failure("Not saved: #{error.record.errors.full_messages.to_sentence}.")
    rescue ActiveRecord::QueryCanceled
      failure("The query ran longer than #{AdminMcp::Tools::Analytics::TIMEOUT_MS / 1000} s and was stopped. Narrow it.")
    end

    def run(_args, _caller) = raise(NotImplementedError)

    private
      def declare(name, title, description, properties, required, write:)
        tool_name name
        title title
        description description
        input_schema(properties:, required:)
        annotations(read_only_hint: !write, destructive_hint: false, idempotent_hint: !write, open_world_hint: false)
      end

      def success(value) = MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(value.as_json) } ])

      def failure(message) = MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)

      # A page of a finder's rows: how many there are in all, and `limit` of them from `offset`.
      def page(scope, args)
        limit = (args[:limit] || DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
        [ scope.count, scope.limit(limit).offset(args[:offset] || 0) ]
      end
  end
end
