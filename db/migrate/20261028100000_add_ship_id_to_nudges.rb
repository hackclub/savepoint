class AddShipIdToNudges < ActiveRecord::Migration[8.1]
  def change
    add_column :nudges, :ship_id, :integer
    add_index :nudges, :ship_id
  end
end
