require "test_helper"

# D-111: every deflation has a reason. From its review on, a ship with fewer hours than it claimed says why, an approved ship's hours are
# its review's less the fraud deduction, and a deduction has its notes. The model refuses a write that breaks a rule. The database
# refuses one that skips the model (test/db/deflation_constraints_test.rb).
class ShipDeflationReasonTest < ActiveSupport::TestCase
  setup do
    travel_to(Program::STARTS_AT + 2.days)
    @ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.", repo_url: "https://github.com/ana/pong",
                                         demo_url: "https://example.com/pong", hours: 5.3, screenshot_shows_game: true,
                                         screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"))
  end

  # The ship as the review leaves it, a hundredth under the 5.3 claimed and with no reason, in `status`.
  def reviewed(status, **more)
    fraud_status = { "awaiting_fraud" => "pending", "approved" => "passed" }[status]
    @ship.assign_attributes({ status:, fraud_status:, claimed_hours: 5.3, review_hours: 5.29, review_coding_hours: 3.75, review_art_hours: 1.54,
                              approved_hours: (5.29 if status == "approved"), deflation_reason: nil }.merge(more))
    @ship
  end

  test "a ship waiting for its fraud check, or approved, needs a reason when its review hours are below the hours claimed" do
    %w[awaiting_fraud approved].each do |status|
      ship = reviewed(status)
      assert_not ship.valid?, status
      assert_equal [ "Say why the hours went down from the 5.3 hrs claimed" ], ship.errors[:deflation_reason], status
      ship.deflation_reason = ""
      assert_not ship.valid?, "#{status}: nothing is no reason"
      ship.deflation_reason = " \n\t "
      assert_not ship.valid?, "#{status}: blank words are no reason"
      ship.deflation_reason = "A menu was cut."
      assert ship.valid?, ship.errors.full_messages.to_sentence
    end
  end

  test "a review at the hours claimed, or above them, needs no reason" do
    assert reviewed("awaiting_fraud", review_hours: 5.3).valid?
    assert reviewed("approved", review_hours: 5.3, approved_hours: 5.3).valid?
    assert reviewed("awaiting_fraud", review_hours: 6).valid?, "more is not a deflation"
  end

  test "a ship with no claim, or not yet at its fraud check, needs no reason" do
    assert reviewed("awaiting_fraud", claimed_hours: nil).valid?, "nothing to fall below"
    assert reviewed("awaiting_fraud", review_hours: nil).valid?
    %w[in_review changes_needed rejected].each do |status|
      assert reviewed(status).valid?, status
    end
  end

  test "an approved ship's hours are its review's hours less the fraud deduction" do
    ship = reviewed("approved", review_hours: 5.3, approved_hours: 5.3)
    assert ship.valid?
    ship.approved_hours = 5.29
    assert_not ship.valid?
    assert_equal [ "Approved hours are the review's hours less the fraud deduction" ], ship.errors[:approved_hours]
    ship.approved_hours = nil
    assert_not ship.valid?, "none is not a pass"
    ship.assign_attributes(approved_hours: 5.3, review_hours: nil)
    assert_not ship.valid?, "no review hours is not a pass either"

    ship.assign_attributes(review_hours: 5.3, approved_hours: 5.3, fraud_deduction_hours: 1, fraud_notes: "An hour was AFK.")
    assert_not ship.valid?, "the deduction comes off"
    ship.approved_hours = 4.3
    assert ship.valid?, ship.errors.full_messages.to_sentence
  end

  test "only an approved ship's hours have to add up" do
    assert reviewed("awaiting_fraud", review_hours: 5.3, approved_hours: nil, deflation_reason: nil).valid?
    assert reviewed("rejected", review_hours: 5.3, approved_hours: nil).valid?
  end

  test "a fraud deduction needs notes, and blank notes are none" do
    ship = reviewed("approved", fraud_status: "deducted", review_hours: 5.3, approved_hours: 4.3, fraud_deduction_hours: 1, fraud_notes: nil)
    assert_not ship.valid?
    assert_equal [ "Say why you deduct hours" ], ship.errors[:fraud_notes]
    ship.fraud_notes = " \n"
    assert_not ship.valid?, "blank notes are none"
    ship.fraud_notes = "An hour of the Lapse was AFK."
    assert ship.valid?, ship.errors.full_messages.to_sentence

    ship.assign_attributes(fraud_deduction_hours: 0, approved_hours: 5.3, fraud_notes: nil)
    assert ship.valid?, "no deduction, no notes"
  end

  test "a deduction needs notes on a ship of any status" do
    ship = reviewed("rejected", fraud_deduction_hours: 1, fraud_notes: nil)
    assert_not ship.valid?
    assert_equal [ "Say why you deduct hours" ], ship.errors[:fraud_notes]
  end

  test "the writers of a review leave a ship the rules accept" do
    reviewer = users(:orpheus)
    projects(:ana).user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
    @ship.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600, hours: 10)
    assert @ship.decide!("approved", by: reviewer, technical_features: "A beat grid.")
    assert @ship.valid?, "waiting for the fraud check: #{@ship.errors.full_messages.to_sentence}"
    assert @ship.deflation_reason.present?, "a cut from the limits is named"
    assert @ship.pass_fraud!(by: reviewer, deduction: "1", notes: "An hour was AFK.")
    assert @ship.valid?, "approved with a deduction: #{@ship.errors.full_messages.to_sentence}"
    assert_equal [ @ship.review_hours - 1, 1 ], [ @ship.approved_hours, @ship.fraud_deduction_hours ]
  end
end
