class CreateSellerRequests < ActiveRecord::Migration[8.1]
  def change
    # Asking for a console from another seller than the shop's (to save on customs): which console, the link to it,
    # and what an admin decided (who, and when).
    create_table :seller_requests do |t|
      t.references :project, null: false, foreign_key: true
      t.string :prize, null: false
      t.string :url, null: false
      t.string :status, null: false, default: "pending"
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.timestamps
    end
    add_index :seller_requests, %i[project_id prize]
  end
end
