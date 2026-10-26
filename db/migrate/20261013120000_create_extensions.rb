class CreateExtensions < ActiveRecord::Migration[8.1]
  def change
    # Asking for more time to ship: once per project, why, and what an admin decided (who, and when). The deadline it
    # moves to is fixed (Program::EXTENSION_DAYS), so it isn't stored.
    create_table :extensions do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.text :reason, null: false
      t.string :status, null: false, default: "pending"
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.timestamps
    end
  end
end
