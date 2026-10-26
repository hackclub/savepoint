# Set when Slack refuses to add this person to the channel for a reason that won't change by trying again
# (a restricted account, a deactivated one). The sweep skips them. See JoinSlackChannelsJob.
class AddSlackChannelsFailedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :slack_channels_failed_at, :datetime
  end
end
