# Every project (Project), newest first: who pledged it, what, where they've got to, and each in full. ?q= narrows it
# by the project's name or idea, or who it's by. ?sort= and ?dir= (D-114) order it by any column (Project::ADMIN_SORT_KEYS),
# before the limit, so the top of "Hours, most first" is the top of every matching project.
class Admin::ProjectsController < Admin::BaseController
  LIMIT = 200

  def index
    @query = params[:q].to_s.strip
    @sort = params[:sort].to_s.presence_in(Project::ADMIN_SORT_KEYS)
    @dir = (params[:dir].to_s.presence_in(%w[asc desc]) || Project::ADMIN_SORT_DEFAULT_DIRECTIONS[@sort]) if @sort
    projects = Project.joins(:user).preload(:user, :ships, pair_as_first: %i[first_project second_project], pair_as_second: %i[first_project second_project])
    projects = projects.search(@query) if @query.present?
    @total = projects.count
    @projects = projects.admin_sorted(@sort, @dir).limit(LIMIT)
    # Everyone's hours since Hackatime time started counting, in one query rather than one each.
    @seconds = StreakActivity.where(user_id: @projects.map(&:user_id), activity_date: Program::FIRST_STREAK_DATE..)
                             .group(:user_id).sum(:coded_seconds)
  end

  def show
    @project = Project.includes(:user, ships: :decided_by).find(params[:id])
    @days = @project.user.streak_activities.where(activity_date: Program::FIRST_STREAK_DATE.., coded_seconds: 1..).order(:activity_date)
  end
end
