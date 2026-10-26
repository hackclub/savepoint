# The analytics tools: the `insights` views (CreateInsightsViews, AddUtmToInsightsViews), the same ones the analytics
# service reads (hackclub/save-point-analytics). The views hold no email, name, address or token, and a person is a user ID.
module AdminMcp::Tools::Analytics
  TIMEOUT_MS = 10_000
  LOCK_TIMEOUT_MS = 2_000
  MAX_ROWS = 500
  # A longer text in one cell is cut, and says how long it was.
  MAX_CELL_CHARS = 2_000
  # A larger row stops the query, so a `repeat('x', 1e9)` never reaches this process.
  MAX_ROW_BYTES = 256_000
  TOO_LARGE = "mcp_row_too_large".freeze

  # What each view holds, for describe_schema. The columns come from the database.
  VIEWS = {
    "users" => "One row per sign-in. slack_hash is the SHA-256 (hex) of the Slack ID: admins are in this view, so leave out the hashes describe_schema lists.",
    "projects" => "One per person: the pledge date and how many Hackatime projects are linked.",
    "streak_activities" => "Seconds coded on one day by one person (activity_date, coded_seconds). 1200 s or more counts for the streak.",
    "ships" => "Each ship: status in_review (also while it waits for its fraud check), approved or rejected (changes needed, or rejected for good), hours, approved_hours and the dates. stage is the stored status: in_review, awaiting_fraud, approved, changes_needed or rejected.",
    "orders" => "Each prize claim: status waiting or ordered, hours, prize_key.",
    "visits" => "Each HTML page view (D-047): the UTM tags, empty when the link had none, the path and the time. No person."
  }.freeze

  # The table of what's there to ask, and how.
  class DescribeSchema < AdminMcp::Tool
    reads "describe_schema", "Describe the analytics views",
          "Lists the views in the insights schema that query_sql can read, with each column and what the view holds, and the hashes of the " \
          "admins' Slack IDs, so a query can leave admins out as the admin numbers do. Read this before query_sql."

    def self.run(_args, _caller)
      columns = ActiveRecord::Base.connection.select_rows(<<~SQL.squish).group_by(&:first)
        select table_name, column_name, data_type from information_schema.columns
        where table_schema = '#{AdminMcp::SqlGuard::SCHEMA}' order by table_name, ordinal_position
      SQL
      { schema: AdminMcp::SqlGuard::SCHEMA, note: "Name a view bare (users) or as insights.users. Nothing outside this schema is readable.",
        views: columns.map { |view, rows| { name: view, about: VIEWS[view], columns: rows.map { |_, name, type| { name:, type: } } } },
        admin_slack_hashes: Funnel.admin_hashes }
    end
  end

  # One read-only SELECT over the views.
  class QuerySql < AdminMcp::Tool
    reads "query_sql", "Run a read-only SQL query",
          "Runs one PostgreSQL SELECT (or WITH, VALUES, TABLE) over the insights views, in a READ ONLY transaction with a #{TIMEOUT_MS / 1000} s " \
          "limit and at most #{MAX_ROWS} rows. Writes, several statements, other schemas, system catalogs and some functions are refused. " \
          "Answers { columns, rows, row_count, truncated }. Run describe_schema first, and prefer the typed finders when one fits.",
          { sql: { type: "string", maxLength: AdminMcp::SqlGuard::MAX_SQL_CHARS, description: "One SELECT statement." },
            max_rows: { type: "integer", minimum: 1, maximum: MAX_ROWS, description: "At most this many rows. Default #{MAX_ROWS}." } },
          required: %w[sql]

    def self.run(args, _caller)
      connection = ActiveRecord::Base.connection
      schemas = connection.select_values("select nspname from pg_namespace")
      text = AdminMcp::SqlGuard.check(args[:sql], schemas:)
      cap = (args[:max_rows] || MAX_ROWS).clamp(1, MAX_ROWS)
      # A row over MAX_ROW_BYTES stops the query with the error TOO_LARGE names.
      wrapped = "select * from (select * from (\n#{text}\n) as mcp_query limit #{cap + 1}) as mcp_capped " \
                "where case when pg_column_size(mcp_capped.*) > #{MAX_ROW_BYTES} then ('#{TOO_LARGE}' || pg_column_size(mcp_capped.*))::int else 1 end = 1"
      result = read_only(connection) { connection.exec_query(wrapped) }
      rows = result.cast_values.first(cap)
      rows = rows.map { |row| Array(result.columns.one? ? [ row ] : row).map { cell(it) } }
      { columns: result.columns, rows:, row_count: rows.size, truncated: result.rows.size > cap }
    rescue ActiveRecord::QueryCanceled
      raise
    rescue ActiveRecord::StatementInvalid => error
      raise AdminMcp::Refused, "A row is larger than #{MAX_ROW_BYTES / 1000} KB. Select fewer columns, or cut long ones with left()." if error.message.include?(TOO_LARGE)

      raise AdminMcp::Refused, "PostgreSQL refused the query: #{error.cause&.message&.lines&.first&.strip || error.message.lines.first.strip}"
    end

    # Runs the block in a transaction that is read only and sees only insights, then rolls it back, so a setting made here
    # never outlives the call (also inside a test's transaction).
    def self.read_only(connection)
      answer = nil
      connection.transaction(requires_new: true) do
        connection.execute("set local transaction_read_only = on")
        connection.execute("set local statement_timeout = #{TIMEOUT_MS}")
        connection.execute("set local lock_timeout = #{LOCK_TIMEOUT_MS}")
        connection.execute("set local search_path = #{AdminMcp::SqlGuard::SCHEMA}")
        answer = yield
        raise ActiveRecord::Rollback
      end
      answer
    end

    # A cell as JSON can carry it: long text cut, dates as ISO text.
    def self.cell(value)
      case value
      when Time, DateTime, ActiveSupport::TimeWithZone then value.iso8601
      when BigDecimal then value.to_f
      when String then value.length > MAX_CELL_CHARS ? "#{value.first(MAX_CELL_CHARS)}... <#{value.length} characters>" : value
      when Hash, Array then (json = value.to_json).length > MAX_CELL_CHARS ? "#{json.first(MAX_CELL_CHARS)}... <#{json.length} characters of JSON>" : value
      else value
      end
    end
  end

  # The funnel the analytics service shows, from the same views (ParticipantFunnel counts it).
  class Funnel < AdminMcp::Tool
    reads "funnel", "The hours funnel",
          "The funnel the analytics service shows, for participants (admins left out): signed in, pledged, linked Hackatime, editor sent time (Hackatime showed some seconds), picked a Hackatime " \
          "project, built their first 20 minutes, past 5 hours, past 10 hours, shipped, ship approved, claimed a prize. Each step counts only people " \
          "who reached every step before it, except that picking a Hackatime project is counted from those who linked, not from editor sent time. Numbers only."

    def self.admin_hashes = ParticipantFunnel.admin_hashes

    def self.run(_args, _caller) = ParticipantFunnel.run
  end
end
