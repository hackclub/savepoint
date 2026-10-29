# D-111: every deflation has a reason. From the review on (a ship waiting for its fraud check, or approved), hours below the hours
# claimed need a deflation reason, an approved ship's hours are the review's less the fraud deduction, and a deduction needs its
# notes. The Ship model checks the same three rules (D-111), and the database now refuses a row that breaks one, so no write
# skips them. A blank text is no reason, and a NULL in a column a rule reads is not a pass.
#
# A ship already in that state is fixed first. Its review is a hundredth or two under the hours claimed, with no reason: the
# limits' round-down took it (Ship::Limits#coding_top now rounds so approving the most stores exactly the most). It takes the
# claimed hours as its review hours, and as its approved hours when it is approved. The difference goes to its art hours (its
# coding hours when it has no art), so the split still adds up. The ship and its project go to Airtable again. This is SQL, not
# the model: nothing is messaged and nothing posts to Slack. A gap wider than that with no reason can't be made up, nor can an
# approved ship whose hours don't add up or a deduction without notes. The migration stops and names those ships.
class RequireAReasonForEveryDeflation < ActiveRecord::Migration[8.1]
  # `~ '\S'` is a character that isn't whitespace.
  REASON = %q((deflation_reason IS NOT NULL AND deflation_reason ~ '\S'))
  NOTES = %q((fraud_notes IS NOT NULL AND fraud_notes ~ '\S'))

  CONSTRAINTS = {
    "ships_deflation_has_reason" =>
      "status NOT IN ('awaiting_fraud', 'approved') OR claimed_hours IS NULL OR review_hours IS NULL OR review_hours >= claimed_hours OR #{REASON}",
    "ships_approved_hours_add_up" =>
      "status <> 'approved' OR (approved_hours IS NOT NULL AND review_hours IS NOT NULL AND approved_hours = review_hours - fraud_deduction_hours)",
    "ships_deduction_has_notes" => "fraud_deduction_hours <= 0 OR #{NOTES}"
  }.freeze

  WHAT = {
    "ships_deflation_has_reason" => "are waiting for their fraud check or approved, with review hours below the hours claimed and no deflation reason",
    "ships_approved_hours_add_up" => "are approved, with approved hours that are not the review's hours less the fraud deduction",
    "ships_deduction_has_notes" => "have a fraud deduction and no fraud notes"
  }.freeze

  FIX = <<~'SQL'
    UPDATE ships
    SET review_art_hours = CASE WHEN review_coding_hours IS NOT NULL AND review_art_hours > 0 THEN review_art_hours + (claimed_hours - review_hours) ELSE review_art_hours END,
        review_coding_hours = CASE WHEN review_coding_hours IS NOT NULL AND COALESCE(review_art_hours, 0) = 0 THEN review_coding_hours + (claimed_hours - review_hours) ELSE review_coding_hours END,
        approved_hours = CASE WHEN status = 'approved' THEN claimed_hours ELSE approved_hours END,
        review_hours = claimed_hours,
        synced_at = NULL,
        updated_at = now()
    WHERE status IN ('awaiting_fraud', 'approved')
      AND claimed_hours IS NOT NULL AND review_hours IS NOT NULL
      AND review_hours < claimed_hours AND claimed_hours - review_hours <= 0.02
      AND (deflation_reason IS NULL OR deflation_reason !~ '\S')
      AND fraud_deduction_hours = 0
    RETURNING id, project_id
  SQL

  def up
    fixed = select_rows(FIX)
    if fixed.any?
      execute "UPDATE projects SET synced_at = NULL, updated_at = now() WHERE id IN (#{fixed.map { Integer(it.last) }.uniq.join(", ")})"
      say "ships #{fixed.map(&:first).join(", ")} took the hours claimed as their review hours, and go to Airtable again"
    end

    CONSTRAINTS.each do |name, expression|
      broken = select_values("SELECT id FROM ships WHERE NOT (#{expression}) ORDER BY id")
      raise "D-111: ships #{broken.join(", ")} #{WHAT.fetch(name)}. Fix each by hand, then migrate again." if broken.any?

      add_check_constraint :ships, expression, name:
    end
  end

  # The hours the migration set stay.
  def down
    CONSTRAINTS.each_key { |name| remove_check_constraint :ships, name: }
  end
end
