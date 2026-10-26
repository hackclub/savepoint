class CreateStreakActivities < ActiveRecord::Migration[8.1]
  def change
    # One row per person per streak day: how long they built on their linked Hackatime projects (from Stardance).
    create_table :streak_activities do |t|
      t.references :user, null: false, foreign_key: true
      t.date :activity_date, null: false
      t.integer :coded_seconds, null: false, default: 0
      t.timestamps
    end
    add_index :streak_activities, %i[user_id activity_date], unique: true

    # The streak as of the last sync, so the leaderboard can sort by it without asking Hackatime, and where streak
    # days start (2am local).
    add_column :users, :current_streak, :integer, null: false, default: 0
    add_column :users, :streak_synced_at, :datetime
    add_column :users, :timezone, :string
  end
end
