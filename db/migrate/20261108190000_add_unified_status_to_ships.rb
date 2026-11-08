# What the Airtable row says about the Unified YSWS automation: "Automation - Status" (for example "2–Submitted") and
# "Automation - Error". The sync reads them back, so the admin ships list can show them with no Airtable call per row.
class AddUnifiedStatusToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :unified_status, :string
    add_column :ships, :unified_error, :text
    add_column :ships, :unified_checked_at, :datetime
  end
end
