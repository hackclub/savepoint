require "test_helper"

class StardanceTest < ActiveSupport::TestCase
  setup do
    @token = ENV["STARDANCE_MCP_TOKEN"]
    ENV["STARDANCE_MCP_TOKEN"] = "token-test"
    @ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                                         repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", hours: 3,
                                         screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
  end

  teardown do
    ENV["STARDANCE_MCP_TOKEN"] = @token
    Web.adapter = nil
  end

  def hex(text) = text.unpack1("H*")

  # A Stardance MCP that knows these repos ({ url => project id }), answering as JSON or as an event stream.
  def stardance_knows(repos, stream: false)
    Web.adapter = lambda do |_method, _url, headers, body|
      assert_equal "Bearer token-test", headers["Authorization"]
      message = JSON.parse(body)
      next Web::Response.new(status: 202, headers: {}, body: "") unless message["id"]

      text = case message.dig("params", "name")
      when "query" then "Query ID: q1\nTotal rows: #{repos.size}\nColumns: repo, project_id"
      when "get_rows"
        rows = repos.map { |url, id| "#{hex(url)} | #{id}" }
        "Rows 1-#{repos.size} of #{repos.size}:\n\nrepo | project_id\n-----------\n#{rows.join("\n")}"
      end
      result = message["method"] == "initialize" ? { protocolVersion: "2025-06-18" } : { content: [ { type: "text", text: } ] }
      answer = { jsonrpc: "2.0", id: message["id"], result: }.to_json
      Web::Response.new(status: 200, headers: { "mcp-session-id" => "s1" }, body: stream ? "event: message\ndata: #{answer}\n\n" : answer)
    end
  end

  test "a repo shipped on Stardance is shipped, with its project ids, however the server answers" do
    [ false, true ].each do |stream|
      stardance_knows({ "https://github.com/Ana/Pong.git" => 74 }, stream:)
      check = Stardance.check(@ship)
      assert check.shipped?
      assert_equal [ 74 ], check.ids
      assert_includes check.message, "https://stardance.hackclub.com/projects/74"
    end
  end

  test "a repo Stardance doesn't have is clear" do
    stardance_knows({ "https://github.com/someone/else" => 9 })
    assert_equal :clear, Stardance.check(@ship).status
  end

  test "it is unknown without a token, or when Stardance fails, and never raises" do
    ENV["STARDANCE_MCP_TOKEN"] = nil
    assert_not Stardance.configured?
    assert Stardance.check(@ship).unknown?

    ENV["STARDANCE_MCP_TOKEN"] = "token-test"
    Web.adapter = ->(*) { raise Web::Error, "boom" }
    assert Stardance.check(@ship).unknown?
    Web.adapter = ->(*) { Web::Response.new(status: 401, headers: {}, body: "") }
    assert Stardance.check(@ship).unknown?
  end

  test "a project with a ship already in the Unified YSWS DB is never blocked" do
    stardance_knows({ "https://github.com/ana/pong" => 74 })
    @ship.update_columns(in_unified: true)
    assert_equal :clear, Stardance.check(@ship).status
  end
end
