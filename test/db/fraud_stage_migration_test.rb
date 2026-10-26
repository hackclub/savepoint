require "test_helper"
require Rails.root.join("db/migrate/20261026100000_add_fraud_stage_to_ships")

# D-063: ships decided before the fraud stage existed keep their meaning. Rejected ships were "changes needed" and approved ships
# were approved with a fraud check passed. The test database already has the new columns, so the migration runs down, then up.
class FraudStageMigrationTest < ActiveSupport::TestCase
  test "existing ships map to the new statuses, and the migration reverses" do
    project = projects(:ana)
    make = ->(title) do
      project.ships.create!(title:, description: "Two paddles, one ball, and every frame is a sprite.", repo_url: "https://github.com/ana/#{title}",
                            demo_url: "https://example.com/#{title}", hours: 5, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                            screenshot_shows_game: true)
    end
    waiting, rejected, approved = make.("waiting"), make.("rejected"), make.("approved")
    rejected.update_columns(status: "changes_needed")
    approved.update_columns(status: "approved", approved_hours: 4.5, decided_by_id: users(:orpheus).id, decided_at: Time.utc(2026, 11, 1, 12))

    ActiveRecord::Migration.suppress_messages do
      migration = AddFraudStageToShips.new
      migration.down
      assert_equal %w[in_review rejected approved], [ waiting, rejected, approved ].map { Ship.connection.select_value("select status from ships where id = #{it.id}") }
      migration.up
    end
    Ship.reset_column_information

    assert_equal "in_review", waiting.reload.status
    assert_nil waiting.fraud_status
    assert_equal "changes_needed", rejected.reload.status, "a rejection was a send-back"
    assert_equal "approved", approved.reload.status
    assert_equal "passed", approved.fraud_status
    assert_equal [ users(:orpheus), BigDecimal("4.5"), Time.utc(2026, 11, 1, 12) ], [ approved.reviewer, approved.review_hours, approved.reviewed_at ]
    assert_equal 4.5, approved.approved_hours
  end
end
