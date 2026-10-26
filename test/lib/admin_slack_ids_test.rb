require "test_helper"

class AdminSlackIdsTest < ActiveSupport::TestCase
  Credentials = Struct.new(:admin_slack_ids)

  test "reads comma and whitespace separated ENV ids" do
    assert_equal %w[U1 U2 U3], AdminSlackIds.resolve(env: { "ADMIN_SLACK_IDS" => "U1, U2\nU3" }, credentials: Credentials.new(nil))
  end

  test "merges ENV with credentials and removes duplicates" do
    assert_equal %w[U1 U2], AdminSlackIds.resolve(env: { "ADMIN_SLACK_IDS" => "U1" }, credentials: Credentials.new(%w[U1 U2]))
  end

  test "uses credentials alone, and is empty when neither is set" do
    assert_equal %w[U2], AdminSlackIds.resolve(env: {}, credentials: Credentials.new(%w[U2]))
    assert_equal [], AdminSlackIds.resolve(env: { "ADMIN_SLACK_IDS" => "" }, credentials: Credentials.new(nil))
  end
end
