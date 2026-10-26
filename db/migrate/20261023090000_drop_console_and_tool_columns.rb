# Save Point has no consoles, sellers or tools: a project is a game and a prize is a key in Prize::ALL. Drops what the
# port from wrong tool left behind. The data goes with it.
class DropConsoleAndToolColumns < ActiveRecord::Migration[8.1]
  def up
    drop_table :seller_requests
    remove_index :orders, name: "index_orders_on_project_id_and_prize"
    remove_column :orders, :prize
    remove_column :orders, :prize_color
    remove_column :orders, :prize_options
    remove_column :orders, :seller_url
    remove_column :projects, :prize
    remove_column :projects, :prize_color
    remove_column :projects, :prize_options
    remove_column :projects, :tool
    remove_column :projects, :tool_name
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
