class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include DevClock if Rails.env.development?

  helper_method :current_user, :signed_in?, :impersonating?, :true_user

  before_action :refuse_writes_while_impersonating
  before_action :remember_timezone
  before_action :record_utm
  before_action :record_presence

  VIEWING_AS_ALERT = "You're viewing as them. Stop viewing as them to do that.".freeze

  private
    # Viewing as someone is read-only: an admin who could write as them could claim their prize to any address, ship
    # or edit their project. Only ending the view (Admin::ImpersonationsController#destroy) and signing out
    # (SessionsController#destroy) get through.
    def refuse_writes_while_impersonating
      return unless impersonating?
      return if request.get? || request.head?
      return if %w[admin/impersonations sessions].include?(controller_path) && action_name == "destroy"

      if request.format.json?
        render json: { error: VIEWING_AS_ALERT }, status: :forbidden
      else
        redirect_back_or_to project_path, alert: VIEWING_AS_ALERT, allow_other_host: false
      end
    end

    # app/javascript/timezone.js keeps the browser's timezone in a cookie. Not while an admin's viewing as someone:
    # that's the admin's browser, not theirs.
    def remember_timezone
      current_user&.remember_timezone(cookies[:timezone]) if cookies[:timezone].present? && !impersonating?
    end

    # Every page view is a visit (D-047), with the UTM tags when the link has them (D-043). The first tags a browser
    # sees are kept in a signed cookie for sign-up to copy (SessionsController). A failure here never breaks the page.
    def record_utm
      return unless trackable_request?

      tags = Visit.tags_from(params)
      Visit.create!(tags.merge(path: request.path.first(200)))
      if tags.values.any? && cookies.signed[:sp_utm].blank?
        cookies.signed[:sp_utm] = { value: tags.to_json, expires: 30.days, httponly: true, same_site: :lax, secure: request.ssl? }
      end
    rescue StandardError => error
      Rails.logger.error("[utm] couldn't record a visit: #{error.class}")
    end

    # The signed-in participant was just here, at most once a minute (D-047). Fails soft like record_utm.
    def record_presence
      current_user&.touch_last_seen(request.path.first(200)) if trackable_request?
    rescue StandardError => error
      Rails.logger.error("[presence] couldn't record presence: #{error.class}")
    end

    # An HTML page view by someone who isn't an admin, outside /admin and the sign-in redirects. Admins leave no
    # trace (D-032), including one viewing as a participant: true_user is the admin behind that.
    def trackable_request?
      request.get? && request.format.html? && !request.path.start_with?("/admin", "/auth") && !true_user&.admin?
    end

    # Who the site's showing: you, or whoever an admin's viewing as (Admin::ImpersonationsController).
    def current_user
      return @current_user if defined?(@current_user)
      @current_user = User.find_by(id: session[:user_id])
    end

    def signed_in?
      current_user.present?
    end

    # An admin's seeing the site as someone else: session[:impersonator_id] is the admin, session[:user_id] who
    # they're viewing as.
    def impersonating?
      session[:impersonator_id].present? && session[:user_id].present?
    end

    # The admin behind an impersonation; otherwise whoever's signed in.
    def true_user
      return current_user unless impersonating?
      return @true_user if defined?(@true_user)
      @true_user = User.find_by(id: session[:impersonator_id])
    end
end
