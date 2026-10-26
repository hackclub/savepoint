# Whether a repository is shipped on Stardance (D-063), copied from playground's StardanceRepos. Stardance has no API, so
# this reads its database through its MCP server (Streamable HTTP, JSON-RPC 2.0): one read-only query for the repos of the
# projects on the playground mission that have a ship event approved or still waiting for review. Stardance reviews such a
# project, so Save Point does not approve it. A project with a ship already in the Unified YSWS DB is never blocked: the
# first into the DB wins. The token is STARDANCE_MCP_TOKEN, a Hack Club Auth sign-in with no refresh. Without it, or when
# Stardance can't be read, the answer is :unknown and the review says so. Never raises from status.
module Stardance
  ENDPOINT = "https://stardance-mcp.cooked.selfhosted.hackclub.com/mcp"
  PROTOCOL = "2025-06-18"
  PAGE = 500
  CACHE_KEY = "stardance-shipped-repos-v2"
  CACHE_FOR = 5.minutes
  MESSAGE = "This project is shipped on Stardance, so it's reviewed there."
  PROJECT_URL = "https://stardance.hackclub.com/projects/%d"
  # certification_status on 2026-10-13 (playground): approved, pending, returned, rejected, misfiled. Empty waits like pending.
  # Text goes hex-encoded, as the MCP's text table can't carry a pipe or a newline.
  SQL = <<~SQL.squish.freeze
    SELECT DISTINCT encode(convert_to(p.repo_url, 'UTF8'), 'hex') AS repo, p.id AS project_id
    FROM stardance.project_mission_attachments pma
    JOIN stardance.projects p ON p.id = pma.project_id AND p.deleted_at IS NULL
    JOIN stardance.missions m ON m.id = pma.mission_id
    JOIN stardance.posts po ON po.project_id = p.id AND po.postable_type = 'Post::ShipEvent'
    JOIN stardance.post_ship_events se ON se.id = po.postable_id
    WHERE m.slug = 'playground' AND pma.deleted_at IS NULL AND pma.detached_at IS NULL
      AND p.repo_url IS NOT NULL AND p.repo_url <> ''
      AND COALESCE(se.certification_status, 'pending') NOT IN ('returned', 'rejected')
    ORDER BY 1, 2
  SQL
  QUESTION = "Which repo URLs, and which Stardance project ids, belong to playground mission projects that have a ship " \
             "on Stardance that is approved or waits for review, so Save Point does not take a project that Stardance reviews?"

  # The server couldn't be read, or answered something this client can't use.
  class Error < StandardError; end

  # A Stardance result for one ship. status: :shipped, :clear, or :unknown. ids: its Stardance project ids.
  Check = Data.define(:status, :ids) do
    def shipped? = status == :shipped
    def unknown? = status == :unknown
    def message = [ MESSAGE, *ids.map { Stardance.project_url(it) } ].join(" ")
  end

  module_function

  def token = ENV["STARDANCE_MCP_TOKEN"].presence
  def configured? = token.present?
  def project_url(id) = format(PROJECT_URL, id)

  # Checks a ship's repository. Once a ship of the project is in the Unified YSWS DB it stays with Save Point.
  def check(ship)
    return Check.new(status: :clear, ids: []) if ship.project.ships.exists?(in_unified: true)

    key = Ship::EarlierShip.normalize(ship.repo_url)
    return Check.new(status: :clear, ids: []) if key.blank?

    ids = index[key]
    Check.new(status: ids ? :shipped : :clear, ids: Array(ids))
  rescue Error, Web::Error, JSON::ParserError => error
    Rails.logger.error("Stardance shipped repos not read (#{error.class})")
    Check.new(status: :unknown, ids: [])
  end

  # { normalized repo => [ Stardance project ids ] }, kept a few minutes so a page load doesn't ask the MCP.
  # A failed read raises and is not kept.
  def index
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_FOR) do
      raise Error, "no Stardance MCP token" unless configured?

      Client.new(token).query(SQL, QUESTION).each_with_object({}) do |(hex, id), found|
        key = Ship::EarlierShip.normalize([ hex ].pack("H*").force_encoding(Encoding::UTF_8))
        next if key.blank?

        (found[key] ||= []) << Integer(id, exception: false)
      end.transform_values { it.compact.uniq.sort }
    end
  end

  # One conversation with the MCP server: initialize opens a session, whose Mcp-Session-Id header goes on every later request.
  class Client
    def initialize(token)
      @token = token
      @next_id = 0
    end

    # The rows of a query, every one read through get_rows, as the query tool's preview cuts long cells short.
    def query(sql, question)
      first = parse_table(call_tool("query", sql:, question:, preview_rows: 1))
      rows = []
      while rows.size < first[:total]
        page = parse_table(call_tool("get_rows", query_id: first[:query_id], offset: rows.size, limit: PAGE))
        raise Error, "get_rows answered no rows at #{rows.size} of #{first[:total]}" if page[:rows].empty?

        rows.concat(page[:rows])
      end
      rows
    end

    private
      def call_tool(name, **arguments)
        open_session unless @opened
        result = rpc("tools/call", name:, arguments:)
        text = Array(result["content"]).select { it["type"] == "text" }.map { it["text"] }.join("\n")
        raise Error, "#{name} failed: #{text.first(200)}" if result["isError"]

        text
      end

      def open_session
        init = rpc("initialize", protocolVersion: PROTOCOL, capabilities: {}, clientInfo: { name: "save-point", version: "1" })
        @protocol = init["protocolVersion"] || PROTOCOL
        @opened = true
        post({ jsonrpc: "2.0", method: "notifications/initialized" })
      end

      def rpc(method, **params)
        id = (@next_id += 1)
        response = post({ jsonrpc: "2.0", id:, method:, params: })
        @session ||= response.headers["mcp-session-id"].presence
        message = answer(response.body, id)
        raise Error, "#{method}: #{message.dig("error", "message")}" if message["error"]

        message.fetch("result")
      end

      def post(message)
        headers = { "Authorization" => "Bearer #{@token}", "Accept" => "application/json, text/event-stream", "Content-Type" => "application/json" }
        headers["Mcp-Session-Id"] = @session if @session
        headers["MCP-Protocol-Version"] = @protocol if @protocol
        response = Web.post(ENDPOINT, headers:, body: message.to_json, timeout: 60)
        raise Error, "Stardance MCP token rejected; sign in again" if response.status == 401
        raise Error, "Stardance answered #{response.status}" unless response.ok?

        response
      end

      # The JSON-RPC answer with this id, from a JSON body or from the events of a server-sent event stream.
      def answer(body, id)
        messages = body.to_s.lstrip.start_with?("{", "[") ? Array.wrap(JSON.parse(body)) : events(body)
        messages.find { it.is_a?(Hash) && it["id"] == id && (it.key?("result") || it.key?("error")) } or
          raise Error, "no answer to request #{id}"
      end

      def events(stream)
        stream.to_s.split(/\r?\n\r?\n/).filter_map do |event|
          data = event.lines.map(&:chomp).select { it.start_with?("data:") }.map { it.delete_prefix("data:").delete_prefix(" ") }
          JSON.parse(data.join("\n")) if data.any?
        end
      end

      # The query and get_rows tools answer a text table:
      #
      #   Query ID: 01f63ae1          (query only)
      #   Total rows: 1               (query; get_rows says "Rows 1-3 of 28:")
      #
      #   repo | project_id
      #   -----------------
      #   6162 | 74
      def parse_table(text)
        lines = text.lines.map(&:rstrip)
        total = text[/^Total rows: (\d+)/, 1] || text[/^Rows \d+-\d+ of (\d+)/, 1] or raise Error, "no row count in: #{text.first(200)}"
        rule = lines.index { it.match?(/\A-+\z/) }
        width = rule ? lines[rule - 1].split("|", -1).size : text[/^Columns: (.*)$/, 1].to_s.split(", ").size
        rows = rule ? lines.drop(rule + 1).take_while(&:present?).map { |line| line.split("|", -1).map(&:strip) } : []
        raise Error, "a row has #{rows.find { it.size != width }.size} cells, not #{width}" if rows.any? { it.size != width }

        { query_id: text[/^Query ID: (\S+)/, 1], total: total.to_i, rows: }
      end
  end
end
