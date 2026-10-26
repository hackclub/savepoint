require "test_helper"

class AdminTokenTest < ActiveSupport::TestCase
  test "a token is spat_ and 32 random bytes, and only its SHA-256 is kept" do
    token, record = AdminToken.generate!(user: users(:orpheus), name: "laptop")
    assert_match AdminToken::PATTERN, token
    assert_equal Digest::SHA256.hexdigest(token), record.token_digest
    assert_not_equal token, AdminToken.generate!(user: users(:orpheus), name: "again").first
    assert_equal record, AdminToken.authenticate(token)
  end

  test "a revoked, unknown or malformed token authenticates nobody" do
    token, record = AdminToken.generate!(user: users(:orpheus), name: "laptop")
    assert_nil AdminToken.authenticate(nil)
    assert_nil AdminToken.authenticate("spat_short")
    assert_nil AdminToken.authenticate("spat_#{"a" * 43}")
    record.revoke!
    assert_nil AdminToken.authenticate(token)
  end

  test "using a token is noted at most once a minute" do
    _, record = AdminToken.generate!(user: users(:orpheus), name: "laptop")
    record.used!
    first = record.last_used_at
    assert_not_nil first
    record.used!
    assert_equal first, record.last_used_at
  end

  test "audit rows hold no free text, only IDs" do
    ids = AdminMcp::Tool.audit_ids(ship_id: 4, user_ids: [ 1, 2 ], query: "ana@hackclub.com", technical_features: "text", project_id: "7", id: 3)
    assert_equal({ "ship_id" => 4, "user_ids" => [ 1, 2 ], "id" => 3 }, ids)
  end
end
