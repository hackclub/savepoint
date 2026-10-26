require "test_helper"

class ExtensionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ADMIN" ]
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "nobody can ask for more time any more" do
    sign_in_as_orpheus
    get project_path
    assert_select ".project__days-extension", 0
    get project_path(edit: "extension")
    assert_select ".project__extension-form", 0

    assert_no_difference -> { Extension.count } do
      post project_extension_path, params: { extension: { reason: "exams" } }
    end
    assert_redirected_to project_path
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
  end

  test "how it went, on the card" do
    sign_in_as_orpheus
    extension = projects(:orpheus).create_extension!(reason: "exams")

    extension.update!(status: "approved")
    get project_path
    assert_select ".project__extension[data-state=approved]", "Extended by 7 days."
    assert_select ".project__event[data-kind=ship] .project__event-day", "2", "everyone's due then now"
    assert_select ".project__schedule-note", /Ship any time up to Nov 2\./

    extension.update!(status: "denied")
    get project_path
    assert_select ".project__extension[data-state=denied]", /No extra days this time/
    assert_select ".project__event[data-kind=ship] .project__event-day", "2"
  end

  private
    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end
end
