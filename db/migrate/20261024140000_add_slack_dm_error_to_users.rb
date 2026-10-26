# Why the bot's last DM to them failed (Slack's error code), kept next to slack_dm_failed_at.
class AddSlackDmErrorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :slack_dm_error, :string
  end
end
