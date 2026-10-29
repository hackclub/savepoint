# D-121: every jame gam submission by a project's person, for the admin pages. Each entry holds only
# {id, jam, game_title, review_status, submitted_at, matches}: never the email, Slack ID, code URL or Hackatime names. `matches` is
# true for this game (Submission#matches?). The two counts cover this game's submissions only and are for sorting. They fill on the
# next JameGamSweepJob (every 30 minutes). No insights view reads these columns.
class AddJameGamSubmissionsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :jame_gam_submissions, :jsonb, null: false, default: []
    add_column :projects, :jame_gam_match_count, :integer, null: false, default: 0
    add_column :projects, :jame_gam_flagged_match_count, :integer, null: false, default: 0
    # The last good lookup: before it, empty columns mean "not checked yet", not a clean record.
    add_column :projects, :jame_gam_checked_at, :datetime
  end
end
