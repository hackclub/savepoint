require "test_helper"

class AirtableClientTest < ActiveSupport::TestCase
  setup { @calls = [] }
  teardown { AirtableClient.adapter = nil }

  def stub(status: 200, body: {})
    AirtableClient.adapter = lambda do |method, url, headers, payload|
      @calls << [ method, url, headers, payload && JSON.parse(payload) ]
      Web::Response.new(status:, headers: {}, body: body.to_json)
    end
  end

  test "needs a token" do
    assert_raises(ArgumentError) { AirtableClient.new(token: nil, base: "appX") }
  end

  test "the token comes from the environment first" do
    ENV["AIRTABLE_PROGRAM_TOKEN"] = "from-env"
    assert_equal "from-env", AirtableClient.program_token
  ensure
    ENV.delete("AIRTABLE_PROGRAM_TOKEN")
  end

  test "upserts in batches of ten, merging on the id field" do
    stub(body: { records: [] })
    AirtableClient.new(token: "pat", base: "appX").upsert("Users", Array.new(11) { { "save_point_id" => "user-#{it}" } }, merge_on: "save_point_id")
    assert_equal 2, @calls.size
    method, url, headers, payload = @calls.first
    assert_equal :patch, method
    assert_equal "https://api.airtable.com/v0/appX/Users", url
    assert_equal "Bearer pat", headers["Authorization"]
    assert_equal [ "save_point_id" ], payload.dig("performUpsert", "fieldsToMergeOn")
    assert_equal 10, payload["records"].size
  end

  test "an error names the status and type, never a value" do
    stub(status: 422, body: { error: { type: "INVALID_VALUE_FOR_COLUMN", message: "Field Email cannot accept the value secret@example.com" } })
    error = assert_raises(AirtableClient::Error) { AirtableClient.new(token: "pat", base: "appX").upsert("Users", [ { "a" => "b" } ], merge_on: "a") }
    assert_equal "Airtable answered 422 INVALID_VALUE_FOR_COLUMN", error.message
  end

  test "refuses the real network in tests" do
    assert_raises(AirtableClient::Error) { AirtableClient.new(token: "pat", base: "appX").tables }
  end

  test "the Unified YSWS DB token comes from the environment first, then credentials" do
    ENV["AIRTABLE_UNIFIED_TOKEN"] = "unified-env"
    assert_equal "unified-env", Ship::EarlierShip.token
  ensure
    ENV.delete("AIRTABLE_UNIFIED_TOKEN")
  end
end
