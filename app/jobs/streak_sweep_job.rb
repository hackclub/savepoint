# Every streak, refreshed from Hackatime, every 10 minutes (D-086): so the bot's cheers (Nudge::Cheer) go out soon after
# someone's 20 minutes, the admin's last-24-hours DAU is current, and streaks that broke overnight show even if nobody's
# looked. Each sync is one request to Hackatime for the person's recent spans. The syncs are spread over SPREAD, not
# sent in one burst, because Hackatime's client has no backoff for being rate limited.
class StreakSweepJob < ApplicationJob
  SPREAD = 3.minutes

  def perform
    User.joins(:project).where.not(hackatime_uid: nil).find_each do |user|
      StreakSyncJob.set(wait: rand(SPREAD.to_i).seconds).perform_later(user.id) if user.project.tracking?
    end
  end
end
