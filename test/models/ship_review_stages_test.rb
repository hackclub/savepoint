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

    ship.update_columns(status: "changes_needed") # a later ship waits for an earlier one in its fraud check (D-109)
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

  # D-111: a participant's ship of 5.3 counted hours, with no AI coding and 5542 s of art. The review stored 5.29 with no reason, because
  # coding and art were each rounded down on their own. Approving the most the rules allow now stores the 5.3 claimed.
  test "approving the most the rules allow stores the hours claimed with no reason, and the fraud check passes them whole (D-111)" do
    @ship.update_columns(hours: 5.3, ai_coding_seconds: 0, art_seconds: 5542)
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    @ship.reload
    assert_equal [ BigDecimal("5.3"), BigDecimal("5.3") ], [ @ship.claimed_hours, @ship.review_hours ]
    assert_equal [ BigDecimal("3.76"), BigDecimal("1.54") ], [ @ship.review_coding_hours, @ship.review_art_hours ], "the hundredth the round-down lost is art's"
    assert_nil @ship.deflation_reason, "nothing was cut"

    assert @ship.pass_fraud!(by: @reviewer)
    assert_equal BigDecimal("5.3"), @ship.reload.approved_hours
    assert_equal 5.3, @project.reload.hours_approved
    assert_nil AirtableFields.deflation(@ship)
    assert_nil AirtableFields.deflation_problem(@ship)
  end

  test "approving the most stores exactly the most, and the claimed hours when nothing is cut, for any hours (D-111)" do
    rng = Random.new(111)
    cut = uncut = 0
    150.times do
      claimed = BigDecimal((rng.rand * 9.99 + 0.01).round(2).to_s)
      ai = rng.rand < 0.4 ? 0 : (rng.rand * claimed.to_f * 3600 * rng.rand).to_i
      art = rng.rand < 0.3 ? 0 : (rng.rand * claimed.to_f * 3600 * rng.rand).to_i
      @ship.update_columns(status: "in_review", fraud_status: nil, reviewer_id: nil, claimed_hours: nil, review_coding_hours: nil, review_art_hours: nil,
                           review_hours: nil, deflation_reason: nil, approved_hours: nil, hours: claimed, ai_coding_seconds: ai, art_seconds: art)
      most = Ship::Limits.new(claimed:, ai_coding_seconds: ai, art_seconds: art).most
      label = [ claimed, ai, art ].inspect

      assert @ship.reload.decide!("approved", by: @reviewer, technical_features: "A rhythm grid."), "#{label}: #{@ship.errors.full_messages.to_sentence}"
      @ship.reload
      assert_equal claimed, @ship.claimed_hours, label
      assert_equal most, @ship.review_hours, label
      assert_equal @ship.review_coding_hours + @ship.review_art_hours, @ship.review_hours, label
      if most < claimed
        cut += 1
        assert @ship.deflation_reason.present?, "a cut is named for #{label}"
      else
        uncut += 1
        assert_nil @ship.deflation_reason, label
      end
      assert @ship.pass_fraud!(by: @reviewer), label
      assert_equal most, @ship.reload.approved_hours, label
    end
    assert_operator cut, :>, 20
    assert_operator uncut, :>, 20
  end

  test "a figure a hundredth below the most needs a reason, and then the ship stores that figure (D-111)" do
    @ship.update_columns(hours: 5.3, ai_coding_seconds: 0, art_seconds: 5542)
    assert_not @ship.decide!("approved", by: @reviewer, coding_hours: "3.75", technical_features: "A rhythm grid.")
    assert_equal [ "Say why you approve fewer hours than the rules allow" ], @ship.errors[:deflation_reason]
    assert @ship.reload.in_review?

    assert @ship.decide!("approved", by: @reviewer, coding_hours: "3.75", technical_features: "A rhythm grid.", deflation_reason: "A menu was cut.")
    @ship.reload
    assert_equal [ BigDecimal("3.75"), BigDecimal("1.53"), BigDecimal("5.28") ], [ @ship.review_coding_hours, @ship.review_art_hours, @ship.review_hours ]
    assert_equal "A menu was cut.", @ship.deflation_reason, "the limits cut nothing, so only the reviewer's words"
  end

  test "hours that went down with no words to say why can't be approved, even when no figure was typed below the limits (D-111)" do
    nothing_to_say = Struct.new(:claimed, :reason) { def approve(*) = [ BigDecimal("2"), BigDecimal("2"), false ] }.new(BigDecimal("5.3"), nil)
    @ship.define_singleton_method(:limits) { |*| nothing_to_say }
    assert_not @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    assert_equal [ "Say why you approve fewer than the 5.3 hrs claimed" ], @ship.errors[:deflation_reason]
    assert @ship.reload.in_review?
    assert_nil @ship.review_hours
  end

  test "a reason given when nothing was cut is not kept" do
    @ship.update_columns(art_seconds: 0, ai_coding_seconds: 0)
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", deflation_reason: "Nothing to say.")
    assert_nil @ship.reload.deflation_reason
    assert_equal 10, @ship.review_hours
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

  # D-112: what the reviewer writes to the participant under Ban is what the rejected ship says. A ship at its fraud check holds
  # the message written under Approve, which was for an approval and isn't the ban's.

  test "a ban at review keeps the message the reviewer typed under Ban" do
    assert @ship.decide!("banned", by: @reviewer, evidence: "The hours are another person's.", feedback: "This is a copy of Pong Remix, so it can't count.")

    assert_equal "This is a copy of Pong Remix, so it can't count.", @ship.reload.review_feedback
  end

  test "a ban at the fraud check drops the message written under Approve, for the default" do
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", feedback: "Loved the boss fight!")
    assert_equal "Loved the boss fight!", @ship.reload.review_feedback

    assert @ship.ban_for_fraud!(by: @reviewer, notes: "Same game as another account.")

    assert_equal "This project was rejected.", @ship.reload.review_feedback
  end

  test "banning the account rejects a ship at its fraud check without the message written under Approve" do
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", feedback: "Loved the boss fight!")

    @project.user.ban!("Fraud.", by: @reviewer)

    @ship.reload
    assert @ship.rejected?
    assert_equal "banned", @ship.fraud_status
    assert_equal "This project was rejected.", @ship.review_feedback
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

  # D-109: shipping again while a ship is in review.

  test "shipping again replaces a ship still waiting for its first review, which leaves every queue and count" do
    first = @ship
    second = @project.ship!(shipping_params)

    assert second.persisted?
    assert second.in_review?
    assert first.reload.superseded?
    assert_equal second, first.superseded_by
    assert_equal [ second ], Ship.pending.where(project: @project).to_a
    assert_equal [ second ], Ship.in_review.where(project: @project).to_a
    assert_equal [ second ], Ship.reviewable.where(project: @project).to_a
    assert_not_includes Ship.decided, first
    assert_equal second, @project.reload.ship_in_review
    assert_equal second, @project.latest_standing_ship, "the replaced ship is not the one that stands"
    assert_equal 0, @project.hours_approved
    assert_equal 0, first.claims.count
  end

  test "a reviewer's verdict on a replaced ship is refused, even from a page opened before it was replaced" do
    open_page = Ship.find(@ship.id)
    @project.ship!(shipping_params)

    assert_not open_page.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    assert_equal [ Ship::REPLACED_MESSAGE ], open_page.errors[:base]
    assert_not open_page.decide!("changes_needed", by: @reviewer, feedback: "More.")
    assert_not open_page.decide!("banned", by: @reviewer, evidence: "Copied.")
    assert @ship.reload.superseded?, "nothing was applied"
    assert_nil @ship.reviewer
    assert_not @reviewer.reload.banned?
    assert_not @project.user.reload.banned?
  end

  test "a ship a reviewer already approved at review is not replaced, and the new ship waits for its fraud check" do
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 2.days).to_date, coded_seconds: 4 * 3600)
    travel 1.hour
    second = ship_again(14)

    assert @ship.reload.awaiting_fraud?, "left alone"
    assert second.in_review?
    assert_equal [ @ship, second ], Ship.pending.where(project: @project).order(:id).to_a
    assert_equal second, @project.reload.latest_standing_ship
    assert_equal @ship, second.waiting_on_earlier
    assert_not_includes Ship.reviewable, second, "not in the review queue until the first is checked"
    assert_not second.decide!("approved", by: @reviewer, technical_features: "More levels.")
    assert_equal [ Ship::WAITING_ON_EARLIER_MESSAGE ], second.errors[:base]
    assert second.reload.in_review?
  end

  test "hours count once: the second ship's review starts from the first ship's approval, not from the start" do
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 2.days).to_date, coded_seconds: 4 * 3600)
    travel 1.hour
    second = ship_again(14)
    second.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
    assert_nil second.earlier_approval, "the first ship is not an approval until its fraud check passes"

    assert @ship.reload.pass_fraud!(by: @reviewer)
    assert_equal 5.71, @project.reload.hours_approved
    assert_equal @ship, second.reload.earlier_approval.ship
    assert_includes Ship.reviewable, second
    assert second.decide!("approved", by: @reviewer, coding_hours: "2", art_hours: "0", technical_features: "More levels.", deflation_reason: "Some of it is repeat work.")
    assert second.pass_fraud!(by: @reviewer)

    new_hours = second.reload.approved_hours - @ship.approved_hours
    assert_equal BigDecimal("2"), new_hours, "only the two new hours were added on top of the first approval"
    assert_equal second.approved_hours.to_f, @project.reload.hours_approved, "the total is the latest approval, not the two added together"
  end

  # D-097, D-111: the later ship's hours are cumulative, so approving the most on the new hours reaches the most on the whole
  # project, and the cut the limits make on it is named.
  test "a later ship approving the most reaches the most on the whole project, with the limits' words for the cut (D-111)" do
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 2.days).to_date, coded_seconds: 4 * 3600)
    travel 1.hour
    second = ship_again(14)
    second.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
    assert @ship.reload.pass_fraud!(by: @reviewer)
    most = Ship::Limits.new(claimed: 14, ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600).most

    assert second.decide!("approved", by: @reviewer, technical_features: "More levels.")
    second.reload
    assert_equal [ BigDecimal("14"), most ], [ second.claimed_hours, second.review_hours ]
    assert_equal second.review_coding_hours + second.review_art_hours, second.review_hours
    assert_match(/AI coding/, second.deflation_reason)
    assert second.pass_fraud!(by: @reviewer)
    assert_equal most, second.reload.approved_hours
    assert_nil AirtableFields.deflation_problem(second)
  end

  test "a later ship approving below the most needs a reason, and a later ship with nothing cut needs none (D-111)" do
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 2.days).to_date, coded_seconds: 4 * 3600)
    travel 1.hour
    second = ship_again(14)
    second.update_columns(ai_coding_seconds: 0, art_seconds: 0)
    assert @ship.reload.pass_fraud!(by: @reviewer)

    assert_not second.decide!("approved", by: @reviewer, coding_hours: "3", technical_features: "More levels.")
    assert_equal [ "Say why you approve fewer hours than the rules allow" ], second.errors[:deflation_reason]
    assert second.decide!("approved", by: @reviewer, technical_features: "More levels.")
    assert_equal [ BigDecimal("14"), BigDecimal("14") ], [ second.reload.claimed_hours, second.review_hours ]
    assert_nil second.deflation_reason
  end

  test "a replaced ship does not reach Airtable or the metrics" do
    first = @ship
    @project.ship!(shipping_params)
    assert first.reload.superseded?
    assert_not_includes Ship.approved, first
    assert_equal 1, Metric.send(:ships).where(project: @project).count, "only the ship that stands"
    assert_not_includes Ship.where(project: @project).latest_per_project, first
  end

  private
    # Shipping through the project, as the form does. The hours the form stores come from Hackatime, so they are set here.
    def ship_again(hours)
      @project.ship!(shipping_params).tap { it.update_columns(hours:) }
    end

    def shipping_params
      { title: "Beat Sheet 2", description: "A rhythm game where every beat is a cell lighting up in time.", changes_made: "More.",
        repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat", screenshot_shows_game: true,
        screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png") }
    end

    def ship_now
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours: 10, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
end
