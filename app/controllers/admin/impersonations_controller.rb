# Seeing the site as someone: an admin becomes them for this session, with their own ID kept aside so they can come
# back (ApplicationController#true_user). Stopping gives the session back to the admin. Only one at a time, never
# yourself, never another admin (User#impersonable_by?). Read-only while it lasts (ApplicationController), and each
# start and stop is an AdminAuditEvent.
class Admin::ImpersonationsController < ApplicationController
  before_action :require_admin, only: :create
  before_action :require_impersonation, only: :destroy

  def create
    user = User.find(params[:user_id])
    return redirect_to admin_users_path, alert: "You can't view as #{user.name}." unless user.impersonable_by?(current_user)

    AdminAuditEvent.create!(user: current_user, tool: "impersonate", ids: { "user_id" => user.id })
    session[:impersonator_id] = current_user.id
    session[:user_id] = user.id
    redirect_to user.project ? project_path : onboarding_path
  end

  def destroy
    admin = true_user
    viewed_id = session[:user_id]
    AdminAuditEvent.create!(user: admin, tool: "stop_impersonating", ids: { "user_id" => viewed_id }) if admin
    session.delete(:impersonator_id)
    if admin
      session[:user_id] = admin.id
      redirect_to admin_users_path
    else
      reset_session
      redirect_to root_path
    end
  end

  private
    def require_admin
      return redirect_to(admin_users_path) if impersonating? # stop viewing as them first
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false unless current_user&.admin?
    end

    def require_impersonation
      redirect_to root_path unless impersonating?
    end
end
