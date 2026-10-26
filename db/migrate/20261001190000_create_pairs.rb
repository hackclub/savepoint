class CreatePairs < ActiveRecord::Migration[8.1]
  def change
    # Two projects building side by side: separate games, one pair streak.
    create_table :pairs do |t|
      t.references :first_project, null: false, foreign_key: { to_table: :projects }, index: { unique: true }
      t.references :second_project, null: false, foreign_key: { to_table: :projects }, index: { unique: true }
      t.date :started_on, null: false
      t.timestamps
    end

    # Your buddy invite link (/b/<code>), and whether you've sent it or said not now.
    add_column :projects, :buddy_code, :string
    add_column :projects, :buddy_invited, :boolean, null: false, default: false
    add_column :projects, :buddy_skipped, :boolean, null: false, default: false
    add_index :projects, :buddy_code, unique: true
  end
end
