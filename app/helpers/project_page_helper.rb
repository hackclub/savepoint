# The project page in Save Point's style (D-009): which of the style sheet's icons stand for what.
module ProjectPageHelper
  # The sidebar rows' icons (ProjectsHelper#project_side_sections names Save Point's) as the style sheet's.
  PROJECT_PAGE_ICONS = {
    "local-fire-department" => "fire-fill", "group" => "user-3-fill", "event" => "calendar-fill", "leaderboard" => "trophy-fill"
  }.freeze

  # The goal's three coins, in ProjectsHelper#project_goal's order: hours logged, daily pace, done by.
  PROJECT_PAGE_GOAL_ICONS = %w[time-fill lightning-fill flag-1-fill].freeze

  def project_page_icon(name, class_name = nil) = sp_icon(PROJECT_PAGE_ICONS.fetch(name, name), class_name)

  def project_page_goal_icon(index) = PROJECT_PAGE_GOAL_ICONS.fetch(index, "star-fill")
end
