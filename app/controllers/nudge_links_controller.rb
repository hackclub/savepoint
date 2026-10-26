# The links in the bot's messages (see Nudge::Message), so we know which ones work. /n/<token> counts the click and
# goes where the button said. /n/<token>/stop asks before stopping his messages, since Slack and browsers sometimes
# open links ahead of time; no sign-in needed, the token's enough.
class NudgeLinksController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  before_action :find_nudge

  def show
    @nudge.clicked!
    redirect_to @nudge.destination_url, allow_other_host: true
  end

  def stop
  end

  def mute
    @nudge.user.mute_slack!(@nudge)
    redirect_to nudge_stop_path(@nudge.token)
  end

  def unmute
    @nudge.user.unmute_slack!(@nudge)
    redirect_to nudge_stop_path(@nudge.token)
  end

  private
    def find_nudge
      @nudge = Nudge.includes(:user).find_by(token: params[:token])
      redirect_to root_path unless @nudge
    end
end
