class AddHackatimeToUsers < ActiveRecord::Migration[8.1]
  def change
    # Linking Hackatime over OAuth: who they are there, and the token (encrypted) that reads their projects and hours.
    add_column :users, :hackatime_uid, :string
    add_column :users, :hackatime_access_token, :text
    add_index :users, :hackatime_uid, unique: true
  end
end
