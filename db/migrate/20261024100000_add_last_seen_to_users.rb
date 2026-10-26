# When and where a participant was last seen (D-047), for the Live now section of the insights page.
class AddLastSeenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_seen_at, :datetime
    add_column :users, :last_seen_path, :string
  end
end
