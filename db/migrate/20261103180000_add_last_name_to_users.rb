# D-143: Hack Club Auth's family name, kept as sent. The Unified YSWS DB row's "Last Name" used to be the full name minus the first
# name, which gave a display name as a last name. Additive only: one nullable column. Users who signed in before it get theirs at
# their next sign-in, and until then AirtableFields.names falls back to the full name minus the first name.
class AddLastNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_name, :string
  end
end
