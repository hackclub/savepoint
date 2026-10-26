# D-086: the DAU tile counts builders in a rolling last 24 hours, which the per-day rows (streak_activities) can't give.
# The sync keeps the last few days of coded time here in 5-minute pieces. The first sync after this ships fills it.
class CreateCodedBuckets < ActiveRecord::Migration[8.1]
  def change
    create_table :coded_buckets do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :bucket_at, null: false
      t.integer :seconds, null: false, default: 0
      t.integer :unconfirmed_seconds, null: false, default: 0
    end
    add_index :coded_buckets, %i[user_id bucket_at], unique: true
    add_index :coded_buckets, :bucket_at
  end
end
