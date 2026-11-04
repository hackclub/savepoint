require "test_helper"
require "rake"

# D-151: Hackatime's ban (trust level red, D-051) bans the person in Save Point.
class HackatimeBanTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:orpheus)
    @user.update_columns(hackatime_uid: "42", hackatime_access_token: "token")
    Rails.application.load_tasks unless Rake::Task.task_defined?("hackatime:ban_red")
    Rake::Task["hackatime:ban_red"].reenable
  end

  def refresh_to(level)
    before = Hackatime.stubbed_trust_levels
    Hackatime.stubbed_trust_levels = { @user.hackatime_uid => level }
    Hackatime.refresh_trust_level!(@user)
  ensure
    Hackatime.stubbed_trust_levels = before
  end

  test "a red trust level bans them with the reason, and the audit log shows Hackatime" do
    assert_difference -> { AdminAuditEvent.where(tool: "hackatime_ban").count }, 1 do
      refresh_to("red")
    end
    @user.reload
    assert @user.banned?
    assert_equal User::HACKATIME_BAN_REASON, @user.ban_reason
    event = AdminAuditEvent.where(tool: "hackatime_ban").last
    assert_nil event.user
    assert_equal({ "user_id" => @user.id }, event.ids)
  end

  test "a stats answer with a red level bans them too" do
    Hackatime.send(:remember_trust_level, @user, { "trust_factor" => { "trust_level" => "red" } })
    assert @user.reload.banned?
  end

  test "someone already banned is left alone" do
    @user.ban!("Fraud.", by: users(:ana))
    banned_at = @user.reload.banned_at
    assert_no_difference -> { AdminAuditEvent.count } do
      refresh_to("red")
    end
    assert_equal "Fraud.", @user.reload.ban_reason
    assert_equal banned_at, @user.banned_at
  end

  test "blue, green and yellow don't ban" do
    %w[blue green yellow].each do |level|
      refresh_to(level)
      assert_not @user.reload.banned?, level
    end
  end

  test "red turning back to blue lifts nothing" do
    refresh_to("red")
    refresh_to("blue")
    assert @user.reload.banned?
  end

  test "a failed ban doesn't break the read that stored the level" do
    User.class_eval do
      alias_method :real_ban!, :ban!
      define_method(:ban!) { |*, **| raise "boom" }
    end
    assert_equal "red", refresh_to("red")
    assert_not @user.reload.banned?
  ensure
    User.class_eval do
      alias_method :ban!, :real_ban!
      remove_method :real_ban!
    end
  end

  test "the backfill bans only red users who aren't banned" do
    ana = users(:ana)
    @user.update_column(:hackatime_trust_level, "red")
    ana.update_column(:hackatime_trust_level, "green")
    banned_red = User.create!(email: "red@example.com", hca_id: "ident!red", slack_id: "U0RED", first_name: "Red", name: "Red One")
    banned_red.update_column(:hackatime_trust_level, "red")
    banned_red.ban!("Fraud.", by: ana)

    out, = capture_io { Rake::Task["hackatime:ban_red"].invoke }

    assert_includes out, "Banned 1 user."
    assert @user.reload.banned?
    assert_equal User::HACKATIME_BAN_REASON, @user.ban_reason
    assert_not ana.reload.banned?
    assert_equal "Fraud.", banned_red.reload.ban_reason
  end
end
