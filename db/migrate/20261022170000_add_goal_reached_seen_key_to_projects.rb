# The goal the "you've earned it" popup was last shown for (Project#goal_reached_popup?), so it shows once per goal.
class AddGoalReachedSeenKeyToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :goal_reached_seen_key, :string
  end
end
