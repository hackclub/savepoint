# A buddy invite link (/b/<code>): who wants to build with you, what you'd both get, and accepting. Anyone can open
# one. Without a project yet, accepting remembers the invite and sends you through onboarding; you're paired once
# you've signed your pledge.
class BuddyInvitesController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  before_action :find_inviter

  def show
    @project = current_user&.project
  end

  def accept
    project = current_user&.project
    unless project
      session[:buddy_code] = @inviter.buddy_code
      return redirect_to onboarding_path
    end

    pair = project.pair_with(@inviter)
    if pair.persisted?
      redirect_to buddy_path
    else
      redirect_to buddy_invite_path(@inviter.buddy_code), alert: pair.errors.full_messages.first
    end
  end

  private
    def find_inviter
      @inviter = Project.includes(:user).find_by(buddy_code: params[:code])
      render "buddy_invites/missing", status: :not_found unless @inviter
    end
end
