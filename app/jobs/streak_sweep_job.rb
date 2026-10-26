# Every streak, refreshed from Hackatime, hourly: so the bot's cheers (Nudge::Cheer) go out within the hour of
# someone's 20 minutes, and ones that broke overnight show it even if nobody's looked.
class StreakSweepJob < ApplicationJob
  def perform
    User.joins(:project).where.not(hackatime_uid: nil).find_each do |user|
      StreakSyncJob.perform_later(user.id) if user.project.tracking?
    end
  end
end
