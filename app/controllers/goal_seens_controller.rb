# The "you've earned it" popup on the project page was shown (goal_popup_controller.js): note it for the goal it was
# shown for, so it doesn't open again for that goal (Project#goal_reached_popup?).
class GoalSeensController < ApplicationController
  def create
    project = current_user&.project
    return head :not_found unless project

    project.goal_reached_seen! if project.goal_reached_popup?
    head :no_content
  end
end
