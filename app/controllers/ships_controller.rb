# Shipping your project: the form, and once it's submitted, that it's in review. Opens once you're set up and your
# hours come from a Hackatime project, and closes after your deadline, with a couple of quiet days' grace
# (Project#ship_cutoff).
class ShipsController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  before_action :require_set_up_project

  def show
    # The live checker asks for the checks that need the internet, as JSON, while the form is filled in.
    if request.format.json?
      checks = Ship::Checklist.new(repo_url: params[:repo_url], demo_url: params[:demo_url]).as_json # cached inside, by repository and by link
      return render json: checks
    end

    @ship = @project.ship_in_review || build_ship
    @rejected = @project.ship_rejected unless @ship.persisted?
    @closed = !@ship.persisted? && !@project.may_ship? && @rejected.nil?
    @needs_nps = !@ship.persisted? && !@closed && @rejected.nil? && NpsResponse.due?(current_user)
    @changes_needed = changes_needed_ship unless @ship.persisted?
    # D-099: an approved ship needs a new hour before the next one. The page says how long is left.
    @waiting = !@ship.persisted? && !@closed && @rejected.nil? && @project.ship_waiting?
    @commits = since_last_ship_commits unless @ship.persisted? || @waiting || @closed || @rejected
  end

  def create
    return redirect_to project_ship_path if @project.ship_in_review || !@project.may_ship? || @project.ship_waiting? || current_user.needs_address? || NpsResponse.due?(current_user)

    @ship = @project.ship!(ship_attributes.merge(changes_required: true))
    if @ship.persisted?

      redirect_to project_ship_path
    else
      @changes_needed = changes_needed_ship
      @commits = since_last_ship_commits
      render :show, status: :unprocessable_entity
    end
  end

  # The ship page's Hackatime list saves a tick or an untick here, as JSON: the page then updates its hours and checklist itself,
  # so nothing typed in the form is touched. The same linking as the project page (ProjectsController#update).
  def hackatime
    @project.load_hackatime_picks
    if @project.update(params.expect(project: [ hackatime_project_names: [] ]))
      render json: { projects: @project.hackatime_projects, hours: helpers.project_hours(@project.hours_logged) }
    else
      render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private
    # D-100: on a later ship, the commits since the latest approved ship, to help write the note. Nil on a first ship, and
    # when GitHub can't say: the list only helps, so nothing is shown and shipping goes on.
    def since_last_ship_commits
      result = Ship::Commits.since_last_ship(@project, @ship.repo_url)
      result if result&.ok? && result.commits.any?
    end

    # The project's newest ship, if an admin said it needs changes: what the participant is fixing now.
    def changes_needed_ship
      latest = @project.ships.order(:id).last
      latest if latest&.changes_needed?
    end

    # A fresh form. Armand's rule: the description and links carry over from your newest ship, so you change them
    # rather than retype them. What you changed since last time and the screenshot start empty on every ship
    # (D-016), and the project's own screenshot is never prefilled.
    def build_ship
      earlier = @project.ships.order(:id).last
      @project.ships.build(title: @project.title, repo_url: @project.repo_url, description: earlier&.description,
                           demo_url: earlier&.demo_url)
    end

    def require_set_up_project
      @project = current_user&.project
      return redirect_to onboarding_path unless @project

      redirect_to project_path unless @project.set_up? && @project.tracking?
    end

    def ship_params
      params.expect(ship: %i[title description changes_made repo_url demo_url screenshot screenshot_signed_id screenshot_shows_game])
    end

    # The form's fields, with the screenshot as a stored blob. A new file is stored at once, so a submit that fails
    # (a short description, say) can carry it to the next try by its signed id, instead of asking for it again. D-016
    # still applies to the carried blob: Ship checks it is new. A signed id is only honoured for a blob this session
    # uploaded and nothing uses yet, since every screenshot's signed id is public in the leaderboard's image URLs.
    def ship_attributes
      attributes = ship_params
      signed_id = attributes.delete(:screenshot_signed_id)
      upload = attributes[:screenshot]
      if upload.respond_to?(:tempfile)
        blob = ActiveStorage::Blob.create_and_upload!(io: upload.tempfile, filename: upload.original_filename,
                                                      content_type: upload.content_type)
        session[:screenshot_blob_ids] = (Array(session[:screenshot_blob_ids]) << blob.id).last(10)
        attributes[:screenshot] = blob
      else
        attributes.delete(:screenshot) # a string would attach whatever blob its signed id names
        blob = carried_blob(signed_id)
        attributes[:screenshot] = blob if blob
      end
      attributes
    end

    # The blob a failed submit carried over: one this session uploaded, that no record has taken yet.
    def carried_blob(signed_id)
      return if signed_id.blank?

      blob = ActiveStorage::Blob.find_signed(signed_id)
      blob if blob && Array(session[:screenshot_blob_ids]).include?(blob.id) && blob.attachments.none?
    end
end
