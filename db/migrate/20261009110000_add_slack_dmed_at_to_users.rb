class AddSlackDmedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :slack_dmed_at, :datetime
  end
end
