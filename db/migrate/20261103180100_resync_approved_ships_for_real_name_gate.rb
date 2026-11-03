# D-143: the sync ticks "Automation - Submit to Unified YSWS" only for a ship whose Real name item is ticked. Rows already copied
# went with the box true, so each approved ship the Unified YSWS DB has not taken goes through the sync once more and has the box
# set false until a reviewer ticks the item. As with D-141, airtable_failed_at is put 50 minutes back so the old pods of a rolling
# deploy, which still send the box true, are gone before the new code sends the row.
class ResyncApprovedShipsForRealNameGate < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE ships
      SET synced_at = NULL,
          airtable_failed_at = GREATEST(airtable_failed_at, now() - interval '50 minutes'),
          updated_at = now()
      WHERE status = 'approved' AND in_unified = false
    SQL
  end

  def down
  end
end
