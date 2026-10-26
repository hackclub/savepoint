# Everyone who's set up, ranked by hours today or in total (D-015). You're on it too, at the bottom until you're set up.
class LeaderboardsController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  SORTS = Leaderboard::SORTS

  def show
    @project = current_user&.project
    return redirect_to onboarding_path unless @project

    @sort = SORTS.include?(params[:sort]) ? params[:sort] : default_sort # old ?sort=week and ?sort=streak links land on the default
    @all = params[:all] == "1" # the whole list instead of your part of it
    current_user.sync_streak_if_stale!
  end

  private

  # Today, always. Total is one tap away (?sort=total).
  def default_sort = "today"
end
