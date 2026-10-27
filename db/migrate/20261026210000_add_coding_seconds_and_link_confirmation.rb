# D-087: the DAU counts only time Hackatime files under "coding", so the coded pieces and streak days keep how much of their
# time that was (coding_seconds, held or not). Null means not asked yet: it reads as all of the time until the next sync
# fills it in. A hand-picked Hackatime link that looks like another game needs a Yes (hackatime_link_confirmed), and a Yes stays.
class AddCodingSecondsAndLinkConfirmation < ActiveRecord::Migration[8.1]
  def change
    add_column :coded_buckets, :coding_seconds, :integer
    add_column :streak_activities, :coding_seconds, :integer
    add_column :projects, :hackatime_link_confirmed, :boolean, default: false, null: false
  end
end
