class AddSlackChannelsJoinedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # When we added them to wrong tool's Slack channels (JoinSlackChannelsJob), so it's only once.
    add_column :users, :slack_channels_joined_at, :datetime
  end
end
