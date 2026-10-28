# Your project: the game you signed up with at the end of onboarding, and setting up to build it.
class ProjectsController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  before_action :require_project, only: %i[show update hours first_heartbeat]

  # ?step= opens one of the setup steps you can still do (otherwise it's the first one left); ?edit=pace, your pace;
  # ?edit=prize, your prize; ?edit=extension, asking for more time (ExtensionsController).
  # ?refresh=1 asks Hackatime for your projects again.
  def show
    @step = params[:step]
    @editing_pace = params[:edit] == "pace"
    @editing_prize = params[:edit] == "prize"
    @asking_extension = params[:edit] == "extension"
    @refresh_hackatime = params[:refresh].present?
    auto_link_hackatime_project(refresh: @refresh_hackatime)
    @refresh_hackatime = false if @project.available_hackatime_projects # just asked: the projects step can use that
    current_user.sync_streak_if_stale!
    # A pace you can no longer finish by the deadline with moves to the slowest one that can.
    if @project.tracking? && !@project.pace_feasible?(@project.pace_minutes) && (pace = @project.feasible_paces.first)
      @project.update_columns(pace_minutes: pace)
    end
  end

  # Your hours, for the pomodoro to keep up to date (and, before you've linked a Hackatime project, for your project
  # page to notice when one links itself); ?refresh=1 asks Hackatime now, otherwise a sync's queued if it's time.
  def hours
    auto_link_hackatime_project(refresh: params[:refresh].present?)
    current_user.sync_streak_if_stale! unless params[:refresh].present?
    hours = @project.hours_logged(refresh: params[:refresh].present?)
    # The sync may have just earned the stickers (Reward.award_stickers!), so the user's rewards are read afresh.
    current_user.rewards.reset
    render json: { hours:, label: helpers.project_hours_label(@project, [ hours - @project.hours_spent, 0 ].max), tracking: @project.tracking?,
                   stickers: helpers.sticker_promise_json(helpers.sticker_promise_state(current_user)), checked_at: Time.current.iso8601 }
  end

  # D-078: whether your first time has reached Hackatime, for the project page's "waiting for your first heartbeat" panel to
  # poll. Hackatime is asked at most once every 30 seconds per person (Project#first_heartbeat_arrived?).
  def first_heartbeat
    render json: { arrived: @project.first_heartbeat_arrived?, checked_at: Time.current.iso8601 }
  end

  # Starting your project (the onboarding controller posts your game, Hackatime project and prize). Once you have
  # one, going through onboarding again leaves it alone and takes you back to your project; you change your prize and
  # pace there. What Save Point doesn't ask for gets a default: every project is a "game" tracked by the Hackatime
  # plugin, builds an hour a day or what its prize needs, in the evening, starting today.
  def create
    return head :unauthorized unless signed_in?

    if (project = current_user.project)
      return render json: { location: accept_pending_buddy_invite(project) ? buddy_path : project_path }
    end

    project = current_user.build_project
    attributes = new_project_attributes
    project.load_hackatime_picks if attributes.key?(:hackatime_project_names)
    if project.update(attributes)
      render json: { location: accept_pending_buddy_invite(project) ? buddy_path : project_path }, status: :created
    else
      render json: { errors: project.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Ticking off a setup step, or changing your project.
  def update
    if setup_params.key?(:hackatime_project_names) || (@project.hackatime_linked? && @project.hackatime_projects.none?)
      @project.load_hackatime_picks
    end
    if @project.update(setup_params)
      # The shop's "Set as my goal" comes back to the shop.
      return head :no_content if request.format.json? # a fetch (the shop's and the picker's) has already drawn the change
      redirect_to(params[:return_to] == "shop" ? shop_path : project_path)
    else
      return render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity if request.format.json?
      @project.restore_attributes([ :build_time ]) # the page draws from the saved one
      @step = "repo" if @project.errors[:repo_url].any?
      @step = "hackatime_project" if @project.errors[:hackatime_projects].any? || @project.hackatime_no_answer?
      render :show, status: :unprocessable_entity
    end
  end

  private
    # Someone followed a buddy invite before they had a project (BuddyInvitesController): now they do, pair them.
    def accept_pending_buddy_invite(project)
      code = session.delete(:buddy_code)
      inviter = Project.find_by(buddy_code: code) if code
      inviter && project.pair_with(inviter).persisted?
    end

    def require_project
      @project = current_user&.project
      redirect_to onboarding_path unless @project
    end

    # Before you've picked a Hackatime project, links the first new one you log time on (Project#auto_link_hackatime_project).
    # Notes what Hackatime has for you to pick from too (left unknown if it can't say right now). Returns the name it
    # linked, if it did.
    def auto_link_hackatime_project(refresh: false)
      return unless @project.hackatime_linked? && @project.hackatime_projects.none?

      @project.available_hackatime_projects = Hackatime.projects(current_user, refresh:)
      @project.auto_link_hackatime_project(@project.available_hackatime_projects)
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      nil
    end

    def pledge_params
      params.expect(project: [ :name, :repo_url, :jame_gam, :prize_key, :build_time, hackatime_project_names: [] ])
    end

    # What onboarding sent, and the defaults for everything else about a project (see #create).
    def new_project_attributes
      sent = pledge_params
      prize = Prize.find(sent[:prize_key])
      attributes = sent.to_h.symbolize_keys
      attributes.delete(:hackatime_project_names) if attributes[:hackatime_project_names].blank?
      build_time = Project::BUILD_TIMES.include?(sent[:build_time]) ? sent[:build_time] : "evening"
      attributes.merge(idea: sent[:name].to_s.strip, signed_on: Date.current,
                       pace_minutes: prize ? Project.pace_for(prize) : Project::PACES.second, build_time:,
                       repo_later: sent[:repo_url].blank?)
    end

    # The screenshot has to be an uploaded file: a string would attach whatever blob its signed id names, and a
    # signed id is public in the leaderboard's image URLs.
    def setup_params
      @setup_params ||= params.expect(project: [ :name, :prize_key, :screenshot, :repo_url, :repo_later, :pace_minutes, :build_time, :party_queued,
                                                 :buddy_invited, :buddy_skipped, :hackatime_auto_linked, :hackatime_link_confirmed, hackatime_project_names: [] ]).tap do |permitted|
        permitted.delete(:screenshot) unless permitted[:screenshot].respond_to?(:tempfile)
      end
    end
end
