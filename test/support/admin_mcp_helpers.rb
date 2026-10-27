require Rails.root.join("db/migrate/20261023150000_create_insights_views")
require Rails.root.join("db/migrate/20261023160100_add_utm_to_insights_views")
require Rails.root.join("db/migrate/20261024110100_add_hackatime_seen_to_insights_projects")
require Rails.root.join("db/migrate/20261026100100_update_insights_ships_for_fraud_stage")
require Rails.root.join("db/migrate/20261026160100_add_retention_data_to_insights_views")
require Rails.root.join("db/migrate/20261027140100_add_faq_reads_to_insights_views")

# Talking to the admin MCP server (Admin::McpController) in an integration test: a token for an admin, a JSON-RPC call,
# and a tool's answer as the Ruby it sent.
module AdminMcpHelpers
  # An admin's token, as the page makes it (shown once): [ the token text, its record ].
  def mcp_token_for(user = users(:orpheus), name: "test")
    AdminToken.generate!(user:, name:)
  end

  def mcp_post(token, method, params = {}, id: 1)
    headers = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
    headers["Authorization"] = "Bearer #{token}" if token
    post admin_mcp_path, params: { jsonrpc: "2.0", id:, method:, params: }.to_json, headers:
  end

  # Calls a tool and returns what it answered: the JSON it sent, or its text when it's an error.
  def mcp_tool(token, name, arguments = {})
    mcp_post(token, "tools/call", { name:, arguments: })
    assert_response :success
    result = response.parsed_body.fetch("result") { flunk("no result: #{response.body}") }
    text = result.dig("content", 0, "text")
    @mcp_error = result["isError"]
    @mcp_error ? text : JSON.parse(text)
  end

  def mcp_error? = @mcp_error

  # Replaces one singleton method of `object` with `replacement` for the block (minitest 6 has no stub).
  def replacing(object, name, replacement)
    original = object.method(name)
    object.define_singleton_method(name) { |*args, **kwargs, &block| replacement.call(*args, **kwargs, &block) }
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  # The insights views are not in schema.rb, so the migrations run for the test, inside its transaction.
  def create_insights_views
    present = ActiveRecord::Base.connection.select_values("select viewname from pg_views where schemaname = 'insights'")
    seen = ActiveRecord::Base.connection.select_value("select 1 from information_schema.columns where table_schema = 'insights' and table_name = 'projects' and column_name = 'hackatime_seen_seconds'")
    return if (CreateInsightsViews::VIEWS + %w[visits nudges site_days faq_reads] - present).empty? && seen

    ActiveRecord::Migration.suppress_messages do
      CreateInsightsViews.new.up
      AddUtmToInsightsViews.new.up
      AddHackatimeSeenToInsightsProjects.new.up
      UpdateInsightsShipsForFraudStage.new.up
      AddRetentionDataToInsightsViews.new.up
      AddFaqReadsToInsightsViews.new.up
    end
  end
end
