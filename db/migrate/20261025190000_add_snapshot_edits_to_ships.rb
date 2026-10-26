# An admin can correct a ship's snapshot (Ship::Snapshot). The ship keeps who did it last and when.
class AddSnapshotEditsToShips < ActiveRecord::Migration[8.1]
  def change
    add_reference :ships, :snapshot_edited_by, foreign_key: { to_table: :users }, null: true
    add_column :ships, :snapshot_edited_at, :datetime
  end
end
