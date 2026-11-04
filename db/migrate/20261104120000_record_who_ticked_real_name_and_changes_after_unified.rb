# The Real name tick is tied to the names it was ticked for: the first and last name, who ticked and when (gate audit finding 5).
# changed_after_unified_at marks an edit made after the Unified YSWS DB took the row, which the sync can no longer send (finding 15).
# Additive only. A tick made before this has no stored names, so it stops counting until a reviewer ticks again.
class RecordWhoTickedRealNameAndChangesAfterUnified < ActiveRecord::Migration[8.1]
  def change
    change_table :ships, bulk: true do |t|
      t.string :real_name_first
      t.string :real_name_last
      t.references :real_name_ticked_by, foreign_key: { to_table: :users }
      t.datetime :real_name_ticked_at
      t.datetime :changed_after_unified_at
    end
  end
end
