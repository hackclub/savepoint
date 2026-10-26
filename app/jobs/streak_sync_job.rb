# Brings one person's streak up to date from Hackatime.
class StreakSyncJob < ApplicationJob
  # from_start: rebuild every day, not only the recent ones (D-055's one-off rebuild).
  def perform(user_id, from_start: false)
    user = User.find_by(id: user_id)
    return unless user

    StreakActivity.sync_for_user!(user, from_start:)
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    # Try again on the next sync.
  end
end
