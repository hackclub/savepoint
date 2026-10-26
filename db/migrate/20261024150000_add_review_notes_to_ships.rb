# What a reviewer writes on a ship: the note the participant sees, their own judgement for the justification, and the
# checklist ticks saved as they go.
class AddReviewNotesToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :review_feedback, :text
    add_column :ships, :review_judgement, :text
    add_column :ships, :review_checklist, :json, default: {}, null: false
  end
end
