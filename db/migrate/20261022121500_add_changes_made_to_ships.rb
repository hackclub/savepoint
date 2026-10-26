# What the participant changed since the game's last version (D-002). Old ships have none.
class AddChangesMadeToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :changes_made, :text
  end
end
