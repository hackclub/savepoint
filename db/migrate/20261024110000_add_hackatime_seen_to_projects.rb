# What Hackatime showed this person the last time we asked: how many projects it listed and the seconds across them,
# since it started counting. Without it "never set up the editor plugin" and "coding on a project that isn't linked"
# look the same from here, because both leave nothing linked.
class AddHackatimeSeenToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :hackatime_seen_count, :integer
    add_column :projects, :hackatime_seen_seconds, :bigint
    add_column :projects, :hackatime_seen_at, :datetime
  end
end
