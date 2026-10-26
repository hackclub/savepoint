# D-063: a ship's review is followed by a fraud check, as on playground. Approving a review moves the ship to
# awaiting_fraud; only a passed fraud check makes it approved, with hours to spend. The stored statuses become
#   in_review (awaiting review), awaiting_fraud, approved, changes_needed, rejected (final, and a fraud ban).
# "rejected" used to mean changes needed, so those rows are renamed first. Approved ships were approved in one step:
# they count as having passed the fraud check, with the review's hours being the approved hours.
class AddFraudStageToShips < ActiveRecord::Migration[8.1]
  def up
    change_table :ships do |t|
      t.bigint :reviewer_id
      t.datetime :reviewed_at
      t.decimal :review_coding_hours, precision: 6, scale: 2
      t.decimal :review_art_hours, precision: 6, scale: 2
      t.decimal :review_hours, precision: 6, scale: 2
      t.string :fraud_status
      t.bigint :fraud_reviewer_id
      t.datetime :fraud_reviewed_at
      t.decimal :fraud_deduction_hours, precision: 6, scale: 2, default: 0, null: false
      t.text :fraud_notes
      t.index :reviewer_id
      t.index :fraud_reviewer_id
      t.index :status
    end
    add_foreign_key :ships, :users, column: :reviewer_id
    add_foreign_key :ships, :users, column: :fraud_reviewer_id

    # Who is working on a ship in one stage. A claim goes stale after its last heartbeat (Claim).
    create_table :claims do |t|
      t.references :ship, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :stage, null: false
      t.datetime :heartbeat_at, null: false
      t.timestamps
      t.index %i[ship_id stage], unique: true
    end

    # A ship that waited for its fraud check and went back to review: the reason, and the review that was cleared.
    create_table :ship_send_backs do |t|
      t.references :ship, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :reason, null: false
      t.jsonb :earlier_review, default: {}, null: false
      t.datetime :created_at, null: false
    end

    change_table :users do |t|
      t.datetime :banned_at
      t.text :ban_reason
    end

    execute "update ships set status = 'changes_needed' where status = 'rejected'"
    execute <<~SQL
      update ships
      set fraud_status = 'passed', reviewer_id = decided_by_id, reviewed_at = decided_at, review_hours = approved_hours
      where status = 'approved'
    SQL
  end

  def down
    execute "update ships set status = 'in_review' where status = 'awaiting_fraud'"
    execute "update ships set status = 'rejected' where status in ('changes_needed', 'rejected')"
    change_table :users do |t|
      t.remove :banned_at, :ban_reason
    end
    drop_table :ship_send_backs
    drop_table :claims
    remove_foreign_key :ships, column: :reviewer_id
    remove_foreign_key :ships, column: :fraud_reviewer_id
    change_table :ships do |t|
      t.remove_index :status
      t.remove :reviewer_id, :reviewed_at, :review_coding_hours, :review_art_hours, :review_hours, :fraud_status,
               :fraud_reviewer_id, :fraud_reviewed_at, :fraud_deduction_hours, :fraud_notes
    end
  end
end
