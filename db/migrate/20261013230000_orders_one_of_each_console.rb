class OrdersOneOfEachConsole < ActiveRecord::Migration[8.1]
  def change
    # Approved hours are spent like money, on as many consoles as they cover: one of each, not one in all.
    remove_index :orders, :project_id, unique: true
    add_index :orders, %i[project_id prize], unique: true
  end
end
