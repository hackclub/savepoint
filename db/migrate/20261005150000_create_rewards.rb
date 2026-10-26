class CreateRewards < ActiveRecord::Migration[8.1]
  def change
    # A streak reward someone's earned, or a pair reward a pair has. Each is earned once; the desktop background,
    # once ever.
    create_table :rewards do |t|
      t.references :user, foreign_key: true
      t.references :pair, foreign_key: true
      t.string :key, null: false
      t.timestamps
    end
    add_index :rewards, %i[user_id key], unique: true
    add_index :rewards, %i[pair_id key], unique: true
    add_index :rewards, :key, unique: true, where: "key = 'desktop'", name: "index_rewards_on_desktop"

    # The day your skip day covered, if it's been used.
    add_column :users, :streak_skip_used_on, :date
  end
end
