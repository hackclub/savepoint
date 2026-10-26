class CreateMetricSnapshots < ActiveRecord::Migration[8.0]
  def change
    # One number per metric per day (Metric), so how wrong tool's numbers moved is on record.
    create_table :metric_snapshots do |t|
      t.date :day, null: false
      t.string :key, null: false
      t.float :value
      t.timestamps
    end
    add_index :metric_snapshots, [ :day, :key ], unique: true
  end
end
