# Hack Club Auth sends people back here. Signing in starts a fresh session (and adds you to Save Point's Slack channels
# the first time); they return to where they came from.
class SessionsController < ApplicationController
  layout "save_point" # for the Hackatime step

  def create
    auth = request.env["omniauth.auth"]
    # Which claims came back, never their values (they're personal).
    Rails.logger.info("[hca] claim keys: #{auth.extra.raw_info.to_h.keys.sort.join(", ")}") if Rails.env.development?
    user = User.from_omniauth(auth, utm: Visit.tags_from_cookie(cookies.signed[:sp_utm])) # first tags seen, for new users (D-043)
    return redirect_to(root_path, alert: "This account can't sign in to Save Point.") if user.banned? # D-063: banned by an admin
    asked_for_address = request.env["omniauth.params"]&.dig("want") == "address"
    return_to = safe_return_path(request.env["omniauth.origin"])
    buddy_code = session[:buddy_code] # a buddy invite accepted before signing in still pairs you after onboarding
    reset_session
    flash[:address_missing] = true if asked_for_address && user.needs_address?
    session[:user_id] = user.id
    session[:buddy_code] = buddy_code if buddy_code
    JoinSlackChannelsJob.perform_later(user.id) unless user.slack_channels_joined_at
    user.remember_timezone(cookies[:timezone]) if cookies[:timezone].present?
    SlackProfileJob.perform_later(user.id) if user.slack_id.present?

    redirect_to after_sign_in_path(user, return_to)
  end

  def failure
    if params[:strategy] == "hackatime"
      # Started by the sign-in chain: they stay signed in, and onboarding offers the link again.
      return redirect_to onboarding_path, alert: hackatime_failed_alert if session.delete(:hackatime_chain)

      return redirect_to project_path, alert: hackatime_failed_alert
    end

    redirect_to onboarding_path, alert: "Couldn't sign you in with Hack Club (#{params[:message].to_s.humanize.downcase})."
  end

  # The page between the two sign-ins. It exists only straight after a Hack Club Auth sign-in (the session flag is
  # used up here), so a link or a reload goes on to onboarding. Its form posts itself to Hackatime's OAuth.
  def hackatime_step
    step = session.delete(:hackatime_step)
    return redirect_to onboarding_path if step.blank? || !signed_in? || current_user.hackatime_linked?

    # The callback reads this to carry on to where they were going (HackatimeLinksController).
    session[:hackatime_chain] = { "return_to" => step["return_to"] }
  end

  def destroy
    reset_session
    redirect_to root_path
  end

  private
    # With no Hackatime token yet, our own Hackatime app set up and HACKATIME_CHAIN=1, sign-in goes on to Hackatime (D-026).
    def after_sign_in_path(user, return_to)
      if Rails.configuration.x.hackatime_chain && !user.hackatime_linked?
        session[:hackatime_step] = { "return_to" => return_to }
        sign_in_hackatime_path
      else
        return_to || onboarding_path
      end
    end

    def hackatime_failed_alert
      "Couldn't link Hackatime (#{params[:message].to_s.humanize.downcase}). Try again."
    end

    # Only paths on this site, so the origin can't send people somewhere else.
    def safe_return_path(origin)
      path = URI.parse(origin.to_s).path.presence
      path if path&.start_with?("/") && !path.start_with?("//")
    rescue URI::InvalidURIError
      nil
    end
end
