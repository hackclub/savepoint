# A cancelled order (Order#cancel!) gives its prize back, so it can be claimed again: the one-per-prize index skips it.
class LetCancelledOrdersFreeTheirPrize < ActiveRecord::Migration[8.1]
  def change
    remove_index :orders, [ :project_id, :prize_key ], unique: true, where: "((prize_key)::text <> 'stickers'::text)", name: "index_orders_on_project_id_and_prize_key"
    add_index :orders, [ :project_id, :prize_key ], unique: true, where: "((prize_key)::text <> 'stickers'::text) AND ((status)::text <> 'cancelled'::text)", name: "index_orders_on_project_id_and_prize_key"
  end
end
