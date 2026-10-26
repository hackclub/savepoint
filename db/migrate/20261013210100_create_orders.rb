class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    # Claiming your console with approved hours: once per project, exactly as picked (console, colour, extras), the
    # hours it took, where it's ordered from (the maker's store, or a seller an admin approved), and an admin
    # ordering it (who, and when).
    create_table :orders do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.string :prize, null: false
      t.string :prize_color, null: false
      t.json :prize_options, default: {}, null: false
      t.decimal :hours, precision: 6, scale: 2, null: false
      t.string :seller_url, null: false
      t.string :status, null: false, default: "waiting"
      t.references :ordered_by, foreign_key: { to_table: :users }
      t.datetime :ordered_at
      t.timestamps
    end
  end
end
