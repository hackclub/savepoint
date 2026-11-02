# D-141: the sync now sets "Automation - Submit to Unified YSWS" on a ship row (as playground's does). The approved ships already
# copied went without it, so each goes through the sync once more, ship 3 (Slime Survivors) included. A ship the Unified YSWS DB has
# taken stays out. While a rolling deploy runs, the old pods still run the sync with the old code, which would send the row without
# the box and stamp it synced. So, as with D-111, airtable_failed_at is put 50 minutes back (or left where it is when it is later):
# ten minutes on, the old pods are gone and the new code sends the row, with the box and with
# AirtableFields.clearing_stale_deflation still applied.
class ResyncApprovedShipsForUnifiedCheckbox < ActiveRecord::Migration[8.1]
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
