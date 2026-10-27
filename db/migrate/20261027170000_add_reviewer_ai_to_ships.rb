# D-102: the reviewer may set a ship's AI coding hours above Hackatime's figure when the code looks AI-generated, with why.
# Nil means the reviewer set none, so Hackatime's figure stands.
class AddReviewerAiToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :reviewer_ai_coding_hours, :decimal, precision: 6, scale: 2
    add_column :ships, :reviewer_ai_reason, :text
  end
end
