require "test_helper"

class SignupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "anyone gets the count, as JSON, and nothing else" do
    Rails.configuration.x.admin_slack_ids = []

    get signups_path

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal({ "count" => User.count }, response.parsed_body)
    assert_match(/public/, response.headers["Cache-Control"])
    assert_no_match(/Orpheus|Ana|U0ORPHEUS|hca_id/, response.body)
  end

  test "admins are not counted" do
    Rails.configuration.x.admin_slack_ids = [ "U0ANA" ]

    get signups_path

    assert_equal User.count - 1, response.parsed_body["count"]
  end

  test "the count is cached briefly" do
    Rails.configuration.x.admin_slack_ids = []
    store = ActiveSupport::Cache::MemoryStore.new

    # Something in a request resets Rails.cache to the null store in some test orders, so pin this one.
    original = Rails.method(:cache)
    Rails.define_singleton_method(:cache) { store }
    begin
      get signups_path
      first = response.parsed_body["count"]
      User.create!(hca_id: "ident!newcomer", first_name: "Newcomer")
      get signups_path
      assert_equal first, response.parsed_body["count"], "still the cached number"
      travel 16.seconds
      get signups_path
      assert_equal first + 1, response.parsed_body["count"]
    ensure
      Rails.define_singleton_method(:cache, original)
    end
  end
end
