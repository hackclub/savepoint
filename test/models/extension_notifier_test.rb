require "test_helper"

class ExtensionNotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0ADMIN" ]
    @extension = projects(:ana).create_extension!(reason: "exams until the 22nd")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "asking DMs each admin why, with a button to decide" do
    ExtensionNotifier.requested(@extension)

    dms = enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
    assert_equal [ "U0ORPHEUS", "U0ADMIN" ], dms.map { |job| job[:args].first }
    assert_equal "Ana Lovelace asked for 7 more days on *pong*:\n>exams until the 22nd", dms.first[:args].second
    assert_equal [ "Decide on Save Point", "https://savepoint.hackclub.com/admin/extensions" ], dms.first[:args].third["link"]
  end

  test "a reason or title with Slack markup is escaped, and a newline can't end the quote" do
    projects(:ana).update!(name: "<!here> pong")
    extension = projects(:orpheus).create_extension!(reason: "a > b\n<!channel> <https://evil.example|x>")
    projects(:orpheus).user.update!(name: "<!everyone> Orph")
    ExtensionNotifier.requested(extension)

    text = enqueued_jobs.find { |job| job[:job] == SlackMessageJob }[:args].second
    assert_includes text, ":\n>a &gt; b &lt;!channel&gt; &lt;https://evil.example|x&gt;"
    assert_includes text, "&lt;!everyone&gt; Orph asked"
    assert_not_includes text, "<!"
    assert_not_includes text, "<https"
    assert_equal 1, text.lines.count - 1, "the quote stays on one line"
  end

  test "a deadline DM escapes the title" do
    projects(:ana).update!(name: "<!channel> pong")
    @extension.decide!("approved", by: users(:orpheus))
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_includes dm[:args].second, "*&lt;!channel&gt; pong*"
  end

  test "a decision is a DM from the bot, with the deadline it leaves them" do
    @extension.decide!("approved", by: users(:orpheus))
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_equal "7 more days! *pong* is due Nov 2 now. Ship it whenever it's playable :)", dm[:args].second
    assert_equal [ "Open Save Point", "https://savepoint.hackclub.com/project" ], dm[:args].third["link"]
    assert_not_nil users(:ana).reload.slack_dmed_at

    clear_enqueued_jobs
    denied = projects(:orpheus).create_extension!(reason: "busy")
    denied.decide!("denied", by: users(:ana))
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_match(/No extra days this time, so \*a rhythm game\* is still due Nov 2/, dm[:args].second)
  end

  test "nothing to someone who stopped the bot's messages, or isn't on Slack" do
    users(:ana).update!(slack_muted_at: Time.current)
    @extension.decide!("approved", by: users(:orpheus))
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }

    users(:orpheus).update!(slack_id: nil)
    projects(:orpheus).create_extension!(reason: "busy").decide!("denied", by: users(:ana))
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
  end
end
