# Everyone who's signed in, newest first, with what they pledged and where they've got to, and a way to see the site
# as them (Admin::ImpersonationsController). ?q= narrows it by name, email, Slack or Hack Club ID. Each person has a
# page of their own too, with their projects.
class Admin::UsersController < Admin::BaseController
  LIMIT = 200

  def index
    @query = params[:q].to_s.strip
    users = User.includes(:project).order(created_at: :desc)
    users = users.search(@query) if @query.present?
    @total = users.count
    @users = users.limit(LIMIT)
  end

  # One person and their projects. A user has one project today, and the page lists projects so it keeps working if that changes.
  def show
    @user = User.includes(project: %i[ships orders]).find(params[:id])
    @projects = Array(@user.project)
  end
end
