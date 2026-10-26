# An order is for a prize in Prize::ALL (prize_key). The old console columns stay for orders made before Save Point,
# and may now be empty on a new order, which has no colour, extras or seller.
class AddPrizeKeyToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :prize_key, :string
    add_index :orders, [ :project_id, :prize_key ], unique: true
    change_column_null :orders, :prize, true
    change_column_null :orders, :prize_color, true
    change_column_null :orders, :seller_url, true
  end
end
