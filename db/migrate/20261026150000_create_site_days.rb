class CreateSiteDays < ActiveRecord::Migration[8.1]
  def change
    create_table :site_days do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :date, null: false
      t.datetime :created_at, null: false
    end
    add_index :site_days, [ :user_id, :date ], unique: true
    add_index :site_days, :date
  end
end
