require "test_helper"

# D-063: a ship's review, then its fraud check, as playground has them. Only a passed fraud check makes a ship approved.
class ShipReviewStagesTest < ActiveSupport::TestCase
  setup do
    @project = projects(:orpheus)
    link_hackatime(@project.user)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
    @reviewer = users(:ana)
    travel_to(Program::STARTS_AT + 2.days)
    @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
    # 10 hours counted, 3 of them AI coding and 4 art: the most is 4 hours of coding and 1.71 of art.
    @ship = ship_now
    @ship.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
  end

  test "approving a review moves the ship to its fraud check, and its hours are not spendable yet" do
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", judgement: "Solid.", feedback: "Nice.")
    @ship.reload
    assert @ship.awaiting_fraud?
    assert_not @ship.approved?
    assert_equal "pending", @ship.fraud_status
    assert_equal @reviewer, @ship.reviewer
    assert_equal [ BigDecimal("4"), BigDecimal("1.71"), BigDecimal("5.71") ], [ @ship.review_coding_hours, @ship.review_art_hours, @ship.review_hours ]
    assert_nil @ship.approved_hours
    assert_nil @ship.decided_at, "not decided yet"
    assert_equal 10, @ship.claimed_hours
    assert_equal @ship, @project.reload.ship_in_review, "to the participant it is still in review"
    assert_not @project.shipped?
    assert_equal 0, @project.hours_approved
    assert_equal 0, @project.hours_to_spend
    assert_not_includes Ship.approved, @ship
    assert_includes Ship.pending, @ship
    assert_not_includes Ship.decided, @ship
  end

  test "coding goes to the AI cap, art to the hold on the approved coding, and below them a reason is due" do
    ship = @ship
    assert ship.decide!("approved", by: @reviewer, coding_hours: "9", art_hours: "5", technical_features: "A rhythm grid.")
    assert_equal [ BigDecimal("4"), BigDecimal("1.71") ], [ ship.review_coding_hours, ship.review_art_hours ], "whatever is typed is held to the limits"

    other = ship_now
    other.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
    assert_not other.decide!("approved", by: @reviewer, coding_hours: "2", technical_features: "A rhythm grid.")
    assert_equal [ "Say why you approve fewer hours than the rules allow" ], other.errors[:deflation_reason]
    assert other.decide!("approved", by: @reviewer, coding_hours: "2", art_hours: "5", technical_features: "A rhythm grid.", deflation_reason: "A menu was cut.")
    assert_equal [ BigDecimal("2"), BigDecimal("0.85") ], [ other.review_coding_hours, other.review_art_hours ], "art held at 30% of the new total"
    assert_match(/A menu was cut\.\z/, other.deflation_reason)
  end

  test "a ship with no art hours approves coding alone" do
    @ship.update_columns(art_seconds: 0)
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    assert_equal [ BigDecimal("8"), BigDecimal("0"), BigDecimal("8") ], [ @ship.review_coding_hours, @ship.review_art_hours, @ship.review_hours ]
  end

  test "changes needed needs the note, and they can ship again" do
    assert_not @ship.decide!("changes_needed", by: @reviewer, feedback: " ")
    assert_equal [ "Tell the participant what to change" ], @ship.errors[:review_feedback]
    assert @ship.reload.in_review?

    assert @ship.decide!("changes_needed", by: @reviewer, feedback: "Add a README.")
    assert @ship.changes_needed?
    assert_equal [ @reviewer, @reviewer ], [ @ship.reviewer, @ship.decided_by ]
    assert_nil @project.reload.ship_in_review
    assert @project.may_ship?
  end

  test "reject is final and needs the judgement" do
    assert_not @ship.decide!("rejected", by: @reviewer, feedback: "No.")
    assert_equal [ "Say what is missing: a reject is final" ], @ship.errors[:review_judgement]
    assert @ship.reload.in_review?

    assert @ship.decide!("rejected", by: @reviewer, judgement: "It is a template with a new title.", feedback: "This is not your own game.")
    assert @ship.rejected?
    assert_equal @ship, @project.reload.ship_rejected
    assert_not @project.may_ship?, "a rejected ship can't be shipped again"
    assert_not @ship.decide!("changes_needed", by: @reviewer, feedback: "x"), "decided already"
  end

  test "fraud at review needs the evidence, rejects the ship and bans the account with its other pending ships" do
    other = ship_now
    assert_not @ship.decide!("banned", by: @reviewer)
    assert_equal [ "Write what shows the fraud" ], @ship.errors[:fraud_notes]
    assert @ship.reload.in_review?
    assert_not @project.user.reload.banned?

    assert @ship.decide!("banned", by: @reviewer, evidence: "The Hackatime hours are another person's.")
    @ship.reload
    assert @ship.rejected?
    assert_equal [ "banned", "The Hackatime hours are another person's.", @reviewer ], [ @ship.fraud_status, @ship.fraud_notes, @ship.fraud_reviewer ]
    assert_equal "This project was rejected.", @ship.review_feedback, "the participant sees a rejection"
    user = @project.user.reload
    assert user.banned?
    assert_equal "The Hackatime hours are another person's.", user.ban_reason
    assert other.reload.rejected?, "another ship still waiting is rejected with the account"
    assert_equal "banned", other.fraud_status
  end

  test "a fraud check passes, and only then is the ship approved with hours to spend" do
    assert_not @ship.pass_fraud!(by: @reviewer), "not reviewed yet"
    @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")

    assert @ship.pass_fraud!(by: users(:orpheus))
    @ship.reload
    assert @ship.approved?
    assert_equal "passed", @ship.fraud_status
    assert_equal BigDecimal("5.71"), @ship.approved_hours
    assert_equal [ users(:orpheus), @reviewer ], [ @ship.fraud_reviewer, @ship.reviewer ]
    assert_equal users(:orpheus), @ship.decided_by
    assert_equal BigDecimal("5.71"), @project.reload.hours_approved
    assert @project.shipped?
    assert_not @ship.pass_fraud!(by: @reviewer), "once"
  end

  test "a deduction takes hours off the review's, and needs notes" do
    @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    assert_not @ship.pass_fraud!(by: @reviewer, deduction: "1.5")
    assert_equal [ "Say why you deduct hours" ], @ship.errors[:fraud_notes]
    assert @ship.reload.awaiting_fraud?

    assert @ship.pass_fraud!(by: @reviewer, deduction: "1.5", notes: "Ninety minutes of the Lapse was AFK.")
    @ship.reload
    assert_equal [ "deducted", BigDecimal("1.5"), BigDecimal("4.21") ], [ @ship.fraud_status, @ship.fraud_deduction_hours, @ship.approved_hours ]
    assert_equal BigDecimal("4.21"), @project.reload.hours_approved

    other = ship_now
    other.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
    other.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    other.pass_fraud!(by: @reviewer, deduction: "99", notes: "None of it.")
    assert_equal BigDecimal("4.21"), other.reload.approved_hours, "a deduction takes only the new hours: the earlier approval stands (D-097)"
  end

  test "a ban at the fraud check rejects the ship for good and bans the account" do
    @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    assert_not @ship.ban_for_fraud!(by: @reviewer, notes: " ")
    assert @ship.reload.awaiting_fraud?

    assert @ship.ban_for_fraud!(by: @reviewer, notes: "Same game as another account.")
    assert @ship.reload.rejected?
    assert_nil @ship.approved_hours
    assert_equal "banned", @ship.fraud_status
    assert @project.user.reload.banned?
    assert_equal 0, @project.reload.hours_approved
  end

  test "a ship waiting for its fraud check goes back to review with a reason, and the page refills from the earlier review" do
    assert_not @ship.send_back_to_review!(by: @reviewer, reason: "x"), "only a ship that waits for the fraud check"
    @ship.update!(review_checklist: { "runs" => true })
    @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", judgement: "Solid.", feedback: "Nice.")

    assert_not @ship.send_back_to_review!(by: users(:orpheus), reason: " ")
    assert_equal [ "Say why it goes back to review" ], @ship.errors[:base]
    assert @ship.reload.awaiting_fraud?

    assert @ship.send_back_to_review!(by: users(:orpheus), reason: "The art hours look high.")
    @ship.reload
    assert @ship.in_review?
    assert_nil @ship.fraud_status
    assert_equal [ nil, nil, nil, nil, nil ], [ @ship.reviewer, @ship.review_hours, @ship.review_judgement, @ship.technical_features, @ship.claimed_hours ]
    assert_equal({}, @ship.review_checklist)

    send_back = @ship.send_backs.sole
    assert_equal [ users(:orpheus), "The art hours look high." ], [ send_back.user, send_back.reason ]
    earlier = send_back.earlier_review
    assert_equal [ "Ana", 4.0, 1.71, 5.71, "A rhythm grid.", "Solid.", "Nice." ],
                 earlier.values_at("reviewer", "coding_hours", "art_hours", "hours", "technical_features", "judgement", "feedback")

    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid, again.")
    assert @ship.reload.awaiting_fraud?, "reviewed again"
  end

  test "a ship is by its project's person" do
    assert @ship.by?(@project.user)
    assert_not @ship.by?(@reviewer)
  end

  test "Limits#approve holds coding to the AI cap and art to the hold, and says when the reviewer went below" do
    limits = Ship::Limits.new(claimed: 10, ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
    assert_equal [ BigDecimal("4"), BigDecimal("1.71"), false ], limits.approve(nil, nil)
    assert_equal [ BigDecimal("4"), BigDecimal("1.71"), false ], limits.approve(BigDecimal("3.995"), BigDecimal("1.705")), "within a rounding of the most is the most"
    assert_equal [ BigDecimal("3"), BigDecimal("1.28"), true ], limits.approve(3, 9)
    assert_equal [ BigDecimal("4"), BigDecimal("1"), true ], limits.approve(9, 1)
    assert_equal [ BigDecimal("0"), BigDecimal("0"), true ], limits.approve(-3, -1)
    unknown = Ship::Limits.new(claimed: 10, ai_coding_seconds: nil, art_seconds: nil)
    assert_equal [ BigDecimal("10"), BigDecimal("0"), false ], unknown.approve(nil, nil), "unknown time cuts nothing"
  end

  test "banning an account rejects its pending ships, and a banned account can't ship" do
    user = @project.user
    user.ban!("Fraud.", by: @reviewer)
    assert user.banned?
    assert @ship.reload.rejected?
    assert_not @project.reload.may_ship?
  end

  private
    def ship_now
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours: 10, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
end
