# A comeback nudge can promise a free sticker pack for coming back (D-078), and notes when it was earned. A project can
# now have up to Reward::STICKER_PACKS_MAX sticker orders, so the one-per-prize index leaves the stickers out.
class AddComebackStickersToNudges < ActiveRecord::Migration[8.1]
  def change
    add_column :nudges, :stickers_promised, :boolean, default: false, null: false
    add_column :nudges, :stickers_earned_at, :datetime

    remove_index :orders, [ :project_id, :prize_key ], unique: true
    add_index :orders, [ :project_id, :prize_key ], unique: true, where: "prize_key <> 'stickers'"
  end
end
