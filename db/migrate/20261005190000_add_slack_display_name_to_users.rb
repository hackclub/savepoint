class AddSlackDisplayNameToUsers < ActiveRecord::Migration[8.1]
  def change
    # The display name they chose on Slack (SlackProfileJob): what everyone else here sees them as, never their real
    # name.
    add_column :users, :slack_display_name, :string
  end
end
