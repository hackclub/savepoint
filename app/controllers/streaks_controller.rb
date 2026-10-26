# Refresh on your streak card: asks Hackatime for your time now, rather than waiting for the next background sync.
class StreaksController < ApplicationController
  def update
    if current_user&.project
      current_user.sync_streak_now!
    end
    redirect_to project_path
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    redirect_to project_path, flash: { streak_alert: "Couldn't reach Hackatime. Try again in a minute." }
  end
end
