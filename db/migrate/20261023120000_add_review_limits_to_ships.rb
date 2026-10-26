# The handbook's hour limits on review (D-030). ai_coding_seconds and art_seconds are Hackatime's "ai coding" and art
# category time on the ship's projects from Save Point's start to the ship (nil: Hackatime has not answered yet).
# claimed_hours is what the ship counted when it was decided. technical_features and deflation_reason are what the
# reviewer wrote, for the Airtable justification fields.
class AddReviewLimitsToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :ai_coding_seconds, :integer
    add_column :ships, :art_seconds, :integer
    add_column :ships, :claimed_hours, :decimal, precision: 6, scale: 2
    add_column :ships, :technical_features, :text
    add_column :ships, :deflation_reason, :text
  end
end
