class AddAddressToUsersAndOrders < ActiveRecord::Migration[8.1]
  def change
    # Where to post things: the address Hack Club Auth shares (its address scope), kept encrypted, and a copy on each
    # order as it was when claimed.
    add_column :users, :address, :text
    add_column :orders, :address, :text
  end
end
