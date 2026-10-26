# Who approved or sent back a ship, and when (Admin::ShipsController).
class AddDecisionToShips < ActiveRecord::Migration[8.1]
  def change
    add_reference :ships, :decided_by, foreign_key: { to_table: :users }, null: true
    add_column :ships, :decided_at, :datetime
  end
end
