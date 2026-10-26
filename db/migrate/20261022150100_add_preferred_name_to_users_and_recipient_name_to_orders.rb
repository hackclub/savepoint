class AddPreferredNameToUsersAndRecipientNameToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :preferred_name, :text
    add_column :orders, :recipient_name, :text
  end
end
