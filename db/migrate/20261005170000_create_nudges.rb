class CreateNudges < ActiveRecord::Migration[8.1]
  def change
    # Every message Clippy sends (see Nudge), with the odds the bandit picked it at, what it said, and what came of it.
    create_table :nudges do |t|
      t.references :user, null: false, foreign_key: true
      t.string :channel, null: false, default: "slack"
      t.string :kind, null: false
      t.string :bucket
      t.string :arm, null: false
      t.integer :variant
      t.string :mood
      t.text :text
      t.text :mood_text
      t.float :propensity
      t.boolean :holdout, null: false, default: false
      # The tracked links (/n/<token>) in the message.
      t.string :token, null: false
      t.datetime :sent_at
      t.boolean :delivered, null: false, default: false
      t.string :slack_channel
      t.string :slack_ts
      t.datetime :clicked_at
      t.integer :clicks, null: false, default: 0
      t.datetime :opted_out_at
      t.integer :reward
      t.datetime :rewarded_at
      t.timestamps
      t.index :token, unique: true
      t.index [ :user_id, :sent_at ]
    end

    # Clicking "stop these messages" in one of Clippy's DMs, and Clippy's bot not being able to DM them at all.
    add_column :users, :slack_muted_at, :datetime
    add_column :users, :slack_dm_failed_at, :datetime
  end
end
