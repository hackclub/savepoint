class AddWeekRankToProjects < ActiveRecord::Migration[8.1]
  def change
    # Where you were on the leaderboard (hours this week) at the last daily snapshot (Leaderboard.snapshot!), and
    # when: the arrows on the leaderboard and Clippy's "passed you" come from it.
    add_column :projects, :week_rank, :integer
    add_column :projects, :week_rank_on, :date
  end
end
