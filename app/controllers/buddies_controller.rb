# The Buddy tab: building alongside someone. Before you're paired, how it works and your invite link; once you are,
# the two of you this week, your pair streak and what it earns.
class BuddiesController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  def show
    @project = current_user&.project
    return redirect_to onboarding_path unless @project

    @buddy = @project.buddy
    current_user.sync_streak_if_stale!
  end
end
