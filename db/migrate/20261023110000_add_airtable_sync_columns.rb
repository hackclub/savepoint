# Bookkeeping for the rolling copy to Airtable (D-027). synced_at is when a row
# was last copied (nil: copy it next). airtable_record_id is the Airtable row.
# airtable_failed_at is when the last copy failed: the row waits an hour.
# in_unified marks an approved ship that the Unified YSWS DB has taken.
class AddAirtableSyncColumns < ActiveRecord::Migration[8.1]
  def change
    %i[users projects orders ships].each do |table|
      add_column table, :synced_at, :datetime
      add_column table, :airtable_record_id, :string
      add_column table, :airtable_failed_at, :datetime
    end
    add_column :ships, :in_unified, :boolean, default: false, null: false
  end
end
