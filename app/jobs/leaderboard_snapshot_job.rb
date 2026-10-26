# Daily: where everyone is on the leaderboard, so tomorrow's board can show who's moved (Leaderboard.snapshot!).
class LeaderboardSnapshotJob < ApplicationJob
  def perform
    Leaderboard.snapshot!
  end
end
