# D-109: a ship the participant replaced by shipping again before its first review has the status "superseded" and points to
# the ship that replaced it.
class AddSupersededByToShips < ActiveRecord::Migration[8.1]
  def change
    add_reference :ships, :superseded_by, foreign_key: { to_table: :ships, on_delete: :nullify }, null: true, index: true
  end
end
