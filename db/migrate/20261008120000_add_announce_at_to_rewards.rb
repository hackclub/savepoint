class AddAnnounceAtToRewards < ActiveRecord::Migration[8.0]
  def change
    # When a reward that's posted in #wrong goes out there: each is given a slot after the last, so they never
    # land together.
    add_column :rewards, :announce_at, :datetime
  end
end
