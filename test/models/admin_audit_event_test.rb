require "test_helper"

class AdminAuditEventTest < ActiveSupport::TestCase
  test "an event needs no admin token: viewing as someone happens on the web" do
    event = AdminAuditEvent.new(user: users(:orpheus), tool: "impersonate", ids: { "user_id" => users(:ana).id })
    assert event.valid?
    event.save!
    assert_nil event.reload.admin_token
  end

  test "an event needs an admin" do
    assert_not AdminAuditEvent.new(tool: "impersonate").valid?
  end
end
