require "test_helper"
require Rails.root.join("db/migrate/20261028120000_require_a_reason_for_every_deflation")

# D-111: the database refuses a ship that breaks a rule of the review, so a write that skips the model (update_columns, SQL, a console)
# can't leave a deflation without its reason. The migration first makes up the hundredth or two that the round-down of an earlier build
# took, and stops, naming the ships, for anything wider.
class DeflationConstraintsTest < ActiveSupport::TestCase
  # Running the migration down and up changes the table's constraints, so forget the statements planned meanwhile.
  teardown { ActiveRecord::Base.connection.clear_cache! }

  def make_ship(project: projects(:ana), title: "Pong")
    project.ships.create!(title:, description: "Two paddles, one ball, and every frame is a sprite.", repo_url: "https://github.com/ana/#{title.parameterize}",
                          demo_url: "https://example.com/#{title.parameterize}", hours: 5.3, screenshot_shows_game: true,
                          screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"))
  end

  # A write the database refuses. The savepoint keeps the test's own transaction usable after it.
  def refused(ship, constraint, **columns)
    error = assert_raises(ActiveRecord::CheckViolation, columns.inspect) { Ship.transaction { ship.update_columns(columns) } }
    assert_match constraint, error.message
  end

  def constraint_names = Ship.connection.check_constraints(:ships).map(&:name)

  test "the three rules are in the schema" do
    assert_includes constraint_names, "ships_deflation_has_reason"
    assert_includes constraint_names, "ships_approved_hours_add_up"
    assert_includes constraint_names, "ships_deduction_has_notes"
  end

  test "a ship waiting for its fraud check, or approved, with review hours below the hours claimed needs a reason" do
    ship = make_ship
    below = { claimed_hours: 5.3, review_hours: 5.29, review_coding_hours: 3.75, review_art_hours: 1.54 }
    refused ship, "ships_deflation_has_reason", status: "awaiting_fraud", fraud_status: "pending", **below, deflation_reason: nil
    refused ship, "ships_deflation_has_reason", status: "awaiting_fraud", fraud_status: "pending", **below, deflation_reason: ""
    refused ship, "ships_deflation_has_reason", status: "awaiting_fraud", fraud_status: "pending", **below, deflation_reason: " \n\t "
    refused ship, "ships_deflation_has_reason", **approved_columns(5.29, **below, deflation_reason: nil)
    refused ship, "ships_deflation_has_reason", **approved_columns(5.29, **below, deflation_reason: "  ")

    ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", **below, deflation_reason: "A menu was cut.")
    ship.update_columns(approved_columns(5.29, **below, deflation_reason: "A menu was cut."))
  end

  test "a review at the hours claimed, with no claim, or not yet at its fraud check needs no reason" do
    ship = make_ship
    assert_nothing_raised do
      ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", claimed_hours: 5.3, review_hours: 5.3, deflation_reason: nil)
      ship.update_columns(status: "awaiting_fraud", claimed_hours: nil, review_hours: 5.29, deflation_reason: nil)
      ship.update_columns(status: "awaiting_fraud", claimed_hours: 5.3, review_hours: nil, deflation_reason: nil)
      %w[in_review changes_needed rejected].each do |status|
        ship.update_columns(status:, fraud_status: nil, claimed_hours: 5.3, review_hours: 5.29, approved_hours: nil, deflation_reason: nil)
      end
    end
  end

  test "an approved ship's hours are its review's hours less the fraud deduction, and none of them missing" do
    ship = make_ship
    ship.update_columns(approved_columns(5.3, claimed_hours: 5.3))
    refused ship, "ships_approved_hours_add_up", approved_hours: 5.29
    refused ship, "ships_approved_hours_add_up", approved_hours: nil
    refused ship, "ships_approved_hours_add_up", review_hours: nil
    refused ship, "ships_approved_hours_add_up", fraud_deduction_hours: 1, fraud_notes: "An hour was AFK."

    ship.update_columns(fraud_status: "deducted", fraud_deduction_hours: 1, fraud_notes: "An hour was AFK.", approved_hours: 4.3)
    ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", approved_hours: nil, fraud_deduction_hours: 0, fraud_notes: nil)
    ship.update_columns(status: "rejected", fraud_status: "banned", approved_hours: nil, review_hours: nil)
  end

  test "a fraud deduction needs notes, on a ship of any status" do
    ship = make_ship
    refused ship, "ships_deduction_has_notes", fraud_deduction_hours: 1, fraud_notes: nil
    refused ship, "ships_deduction_has_notes", fraud_deduction_hours: 1, fraud_notes: ""
    refused ship, "ships_deduction_has_notes", status: "rejected", fraud_deduction_hours: 0.01, fraud_notes: " \n "

    ship.update_columns(fraud_deduction_hours: 1, fraud_notes: "An hour was AFK.")
    ship.update_columns(fraud_deduction_hours: 0, fraud_notes: nil)
  end

  # D-111: a ship approved with 5.29 hours of the 5.3 claimed, no reason, from the round-down.
  def stored_before_the_rule(project, title, status: "approved", coding: 3.76, art: 1.53, review: 5.29, claimed: 5.3, reason: nil, deduction: 0, notes: nil, failed_at: nil)
    ship = make_ship(project:, title:)
    ship.update_columns(status:, fraud_status: (status == "approved" ? "passed" : "pending"), claimed_hours: claimed, review_coding_hours: coding, review_art_hours: art,
                        review_hours: review, approved_hours: (review - deduction if status == "approved"), deflation_reason: reason,
                        fraud_deduction_hours: deduction, fraud_notes: notes, synced_at: Time.utc(2026, 10, 28, 17), updated_at: Time.utc(2026, 10, 28, 17),
                        airtable_failed_at: failed_at)
    ship
  end

  # Each run in a savepoint, as a migration runs in a transaction: one that stops leaves the database as it was.
  def migrate_up = ActiveRecord::Migration.suppress_messages { Ship.transaction(requires_new: true) { RequireAReasonForEveryDeflation.new.up } }
  def migrate_down = ActiveRecord::Migration.suppress_messages { RequireAReasonForEveryDeflation.new.down }

  test "the migration makes up a hundredth a ship lost with no reason, and sends the project at once and the ship ten minutes on" do
    migrate_down
    project = projects(:ana)
    project.update_columns(synced_at: Time.utc(2026, 10, 28, 17))
    both = stored_before_the_rule(project, "Both parts")
    coding_only = stored_before_the_rule(project, "Coding only", coding: 5.29, art: 0, failed_at: 5.minutes.ago)
    waiting = stored_before_the_rule(project, "Waiting", status: "awaiting_fraud")
    two = stored_before_the_rule(project, "Two hundredths", coding: 3.75, art: 1.53, review: 5.28)
    explained = stored_before_the_rule(project, "Explained", reason: "A menu was cut.")
    whole = stored_before_the_rule(project, "Whole", coding: 3.76, art: 1.54, review: 5.3)
    other = projects(:orpheus)
    other.update_columns(synced_at: Time.utc(2026, 10, 28, 17))

    migrate_up

    both.reload
    assert_equal [ BigDecimal("5.3"), BigDecimal("5.3"), BigDecimal("3.76"), BigDecimal("1.54") ],
                 [ both.review_hours, both.approved_hours, both.review_coding_hours, both.review_art_hours ], "the hundredth goes to its art"
    assert_equal [ nil, BigDecimal("5.3") ], [ both.deflation_reason, both.claimed_hours ]
    assert_nil both.synced_at, "it goes to Airtable again"
    assert_operator both.updated_at, :>, Time.utc(2026, 10, 28, 17)
    assert_nil project.reload.synced_at, "and so does its project"
    assert_nil project.airtable_failed_at, "at once: its fields don't change with D-111"
    assert_equal Time.utc(2026, 10, 28, 17), other.reload.synced_at, "another project is left alone"

    # The sync skips a row for an hour after a failure. The ship is put 50 minutes into that, so the old pods of a rolling deploy, which
    # send it without clearing its old deflation sentence, leave it for the new code to send ten minutes on.
    wait = Airtable::SyncJob::FAILED_WAIT
    assert_operator both.airtable_failed_at, :>, wait.ago, "not due now"
    assert_operator both.airtable_failed_at, :<, (wait - 15.minutes).ago, "due within fifteen minutes"

    coding_only.reload
    assert_equal [ BigDecimal("5.3"), BigDecimal("5.3"), BigDecimal("5.3"), BigDecimal("0") ],
                 [ coding_only.review_hours, coding_only.approved_hours, coding_only.review_coding_hours, coding_only.review_art_hours ], "with no art it goes to its coding"
    assert_in_delta 5.minutes.ago.to_f, coding_only.airtable_failed_at.to_f, 60, "a failure later than that stays"
    waiting.reload
    assert_equal [ BigDecimal("5.3"), nil, BigDecimal("1.54") ], [ waiting.review_hours, waiting.approved_hours, waiting.review_art_hours ], "a ship at its fraud check has no approved hours yet"
    assert_nil waiting.airtable_failed_at, "and was never sent, so it has no wait"
    two.reload
    assert_equal [ BigDecimal("5.3"), BigDecimal("5.3"), BigDecimal("3.75"), BigDecimal("1.55") ],
                 [ two.review_hours, two.approved_hours, two.review_coding_hours, two.review_art_hours ], "two hundredths too"

    assert_equal [ BigDecimal("5.29"), "A menu was cut.", Time.utc(2026, 10, 28, 17), nil ],
                 [ explained.reload.review_hours, explained.deflation_reason, explained.synced_at, explained.airtable_failed_at ], "a ship with its reason is left alone"
    assert_equal [ Time.utc(2026, 10, 28, 17), nil ], [ whole.reload.synced_at, whole.airtable_failed_at ], "so is one that lost nothing"
    assert_equal BigDecimal("5.3"), whole.review_hours
    assert_equal [ both, coding_only, waiting, two, explained, whole ].map { it.review_coding_hours + it.review_art_hours }, [ both, coding_only, waiting, two, explained, whole ].map(&:review_hours),
                 "every split still adds up"
    assert_includes constraint_names, "ships_deflation_has_reason"
  end

  test "the migration stops, naming the ships, for a gap past two hundredths, a deduction with no notes, and hours that don't add up" do
    migrate_down
    project = projects(:ana)
    wide = stored_before_the_rule(project, "Wide", coding: 3.74, art: 1.53, review: 5.27)
    deducted = stored_before_the_rule(project, "Deducted", deduction: 0.5, notes: nil, reason: "A menu was cut.")
    off = stored_before_the_rule(project, "Off", reason: "A menu was cut.")
    off.update_columns(approved_hours: 5.0)

    error = assert_raises(RuntimeError) { migrate_up }
    assert_match(/D-111: ships #{wide.id} are waiting for their fraud check or approved, with review hours below the hours claimed and no deflation reason/, error.message)
    assert_not_includes constraint_names, "ships_deflation_has_reason"

    wide.update_columns(deflation_reason: "The levels were copied.")
    error = assert_raises(RuntimeError) { migrate_up }
    assert_match(/D-111: ships #{off.id} are approved, with approved hours that are not the review's hours less the fraud deduction/, error.message)

    off.update_columns(approved_hours: 5.29)
    error = assert_raises(RuntimeError) { migrate_up }
    assert_match(/D-111: ships #{deducted.id} have a fraud deduction and no fraud notes/, error.message)

    deducted.update_columns(fraud_notes: "Half an hour was AFK.")
    migrate_up
    assert_equal %w[ships_approved_hours_add_up ships_deduction_has_notes ships_deflation_has_reason], constraint_names.grep(/\Aships_(deflation|approved|deduction)/).sort
  end

  test "the migration reverses by removing the rules, and leaves the hours it set" do
    migrate_down
    assert_not_includes constraint_names, "ships_deflation_has_reason"
    assert_not_includes constraint_names, "ships_approved_hours_add_up"
    assert_not_includes constraint_names, "ships_deduction_has_notes"
    ship = stored_before_the_rule(projects(:ana), "Down and up")
    migrate_up
    assert_equal BigDecimal("5.3"), ship.reload.approved_hours
    migrate_down
    assert_equal BigDecimal("5.3"), ship.reload.approved_hours, "the hours stay"
    migrate_up
    assert_includes constraint_names, "ships_deduction_has_notes"
  end
end
