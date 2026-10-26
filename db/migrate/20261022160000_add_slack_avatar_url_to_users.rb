class AddSlackAvatarUrlToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :slack_avatar_url, :string
  end
end
