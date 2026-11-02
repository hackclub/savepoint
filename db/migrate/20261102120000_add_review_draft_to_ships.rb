# D-135: the review form's draft, kept on the ship as the reviewer types. Additive only: a jsonb with a constant default and three
# nullable columns, so a live table is not rewritten. A draft decides nothing (Ship#save_review_draft!). No insights view reads these.
class AddReviewDraftToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :review_draft, :jsonb, null: false, default: {}
    add_column :ships, :review_draft_updated_at, :datetime
    add_column :ships, :review_draft_updated_by_id, :bigint
  end
end
