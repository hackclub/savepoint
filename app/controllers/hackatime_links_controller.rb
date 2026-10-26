# Hackatime sends you back here once you've let us read your projects and hours. We ask it who you are, keep that
# and the token, and tick off linking Hackatime on your project. The bot congratulates you if that was the last
# setup step left.
class HackatimeLinksController < ApplicationController
  # A GET, so the read-only rule for viewing as someone misses it: it would link the admin's Hackatime to them.
  before_action :refuse_while_impersonating, only: :create

  def create
    return redirect_to onboarding_path unless signed_in?

    chain = session.delete(:hackatime_chain)
    # Only the page the sign-in chain showed counts: a stale flag must not redirect a link made from elsewhere.
    chain = nil unless request.env["omniauth.origin"].to_s.end_with?(sign_in_hackatime_path)
    token = request.env.dig("omniauth.auth", "credentials", "token").to_s
    uid = Hackatime.user_id(token) if token.present?
    return redirect_to project_path, alert: "Couldn't tell who you are on Hackatime. Try again." if uid.blank?

    if current_user.update(hackatime_uid: uid, hackatime_access_token: token)
      Hackatime.forget(current_user)
      note_hackatime_projects_you_have
      redirect_to after_link_path(chain)
    else
      redirect_to project_path, alert: "That Hackatime account #{current_user.errors[:hackatime_uid].first}."
    end
  end

  private
    # Not back to where they came from: that's Hackatime's OAuth page.
    def refuse_while_impersonating
      redirect_to project_path, alert: VIEWING_AS_ALERT if impersonating?
    end

    # Where a participant goes once Hackatime is linked. After the sign-in chain, on to where they were going.
    def after_link_path(chain)
      return project_path unless chain

      chain["return_to"] || (current_user.project&.setup_finished? ? project_path : onboarding_path)
    end

    # The projects you already have on Hackatime, so the first new one can link itself (Project#auto_link_hackatime_project).
    # If Hackatime can't say right now, the project page notes them instead.
    def note_hackatime_projects_you_have
      return unless (project = current_user.project)

      project.available_hackatime_projects = Hackatime.projects(current_user)
      project.auto_link_hackatime_project(project.available_hackatime_projects)
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    end
end
