class CreateBuddyPomodoros < ActiveRecord::Migration[8.1]
  def change
    # A pomodoro two buddies do together: who started it, how long, from when, and when the other joined.
    create_table :buddy_pomodoros do |t|
      t.references :pair, null: false, foreign_key: true
      t.references :started_by, null: false, foreign_key: { to_table: :projects }
      t.integer :minutes, null: false
      t.datetime :started_at, null: false
      t.datetime :joined_at
      t.timestamps
    end
  end
end
