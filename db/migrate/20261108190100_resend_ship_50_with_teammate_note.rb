# D-156: ship 50 (a teammate's ship on a repo ship 51 already put in Unified) was rejected as a duplicate, because its row had no
# "Optional - Override Duplicate Justification". The sync now fills it. So the ship goes through the sync once more, and
# Airtable::SyncJob unticks and reticks a row that sits in an error so the automation runs again. As with D-141's resync,
# the old pods of a rolling deploy still run the old code, so airtable_failed_at is put 50 minutes back: ten minutes on,
# the new code sends it.
class ResendShip50WithTeammateNote < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE ships
      SET synced_at = NULL,
          airtable_failed_at = GREATEST(airtable_failed_at, now() - interval '50 minutes'),
          updated_at = now()
      WHERE id = 50 AND status = 'approved' AND in_unified = false
    SQL
  end

  def down
  end
end
