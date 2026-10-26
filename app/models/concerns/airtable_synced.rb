# A row that the rolling copy writes to Airtable (Airtable::SyncJob). When one of
# the model's AIRTABLE_COLUMNS changes, synced_at goes back to nil and the row is
# copied next.
module AirtableSynced
  extend ActiveSupport::Concern

  included do
    after_update :mark_unsynced, if: -> { (saved_changes.keys & self.class::AIRTABLE_COLUMNS).any? }
  end

  # The updated_at too, so a copy that was already reading the row does not stamp it synced (Airtable::SyncJob).
  def mark_unsynced = update_columns(synced_at: nil, updated_at: Time.current)
end
