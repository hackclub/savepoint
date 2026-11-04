# D-148: a reviewer who approves past a gate (Stardance unreadable, limits unknown, another program's overlap, a second account on
# the repo or person) types a reason. It is kept with the ship: { "limits" => { "reason" => ..., "by" => user id, "at" => time } }.
class AddReviewOverridesToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :review_overrides, :jsonb, default: {}, null: false
  end
end
