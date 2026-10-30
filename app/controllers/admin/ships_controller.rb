# Every ship (Ship), to inspect: waiting first, oldest at the top, then decided, with a tab per stage. Each opens in full,
# screenshot and all, as playground's review does (D-063). A ship goes through two looks:
#
# - review (in_review): approve it with the coding and art hours (the handbook's limits apply, D-030), ask for changes
#   (a note for the participant, D-049), reject it for good (a judgement), or call it fraud and ban the account (evidence).
# - the fraud check (awaiting_fraud, after an approved review): pass it, pass it with a deduction (notes), or ban. Only a
#   pass makes it approved, with hours to spend. It can instead go back to review, with a reason.
#
# Nobody's told by this page (D-034). An admin can't review or fraud-check their own ship, and a claim (Claim) keeps two
# admins off the same ship. The queues (Admin::QueuesController) hand out the oldest ship waiting.
class Admin::ShipsController < Admin::BaseController
  before_action :set_ship, except: :index
  before_action :refuse_own_ship, only: %i[review fraud send_back hours_start lapse_split reviewer_ai]

  def index
    @stage = params[:stage].presence_in(Ship::STAGES.keys)
    @counts = Ship.group(:status).count.tap { it.default = 0 }
    ships = Ship.includes(:decided_by, project: :user)
    @in_review = ships.in_review.order(:created_at)
    @awaiting_fraud = ships.awaiting_fraud.order(:reviewed_at, :id)
    @superseded = ships.superseded.order(updated_at: :desc)
    @decided = ships.decided.order(decided_at: :desc)
    @decided = @decided.where(status: @stage) if @stage.in?(%w[approved changes_needed rejected])
  end

  def show
    # Asked once, while it's in review, and kept: the AI coding and art time the limits read.
    @ship.fetch_hackatime_categories!
    load_review
  end

  # A review's verdict: params[:decision] is one of Ship::DECISIONS.
  def review
    return head(:bad_request) unless Ship::DECISIONS.include?(params[:decision].to_s)
    return replaced if @ship.superseded?
    return stale unless @ship.in_review?
    return taken if Claim.held_by_other?(@ship, "review", current_user)

    # D-063 item 9: Stardance reviews a repo shipped there, so Approve is refused. Changes needed and reject stay open.
    if params[:decision].to_s == "approved" && Ship::Evidence.new(@ship).stardance_shipped?
      return redirect_to(admin_ship_path(@ship, queue: params[:queue].presence), alert: "This repo is shipped on Stardance, so Stardance reviews it. Approve is off.")
    end
    earlier = Ship::EarlierShip.for(@ship)
    decided = @ship.decide!(params[:decision].to_s, by: current_user, coding_hours: params[:coding_hours], art_hours: params[:art_hours],
                            technical_features: params[:technical_features], deflation_reason: params[:deflation_reason],
                            feedback: params[:review_feedback], judgement: params[:review_judgement], evidence: params[:evidence],
                            checklist_defaults: @ship.checklist_defaults(earlier:))
    return replaced if @ship.superseded?
    return refill unless decided

    @ship.claims.where(stage: "review").delete_all
    done(admin_review_path)
  end

  # A fraud check's verdict: params[:verdict] is one of Ship::FRAUD_VERDICTS.
  def fraud
    return head(:bad_request) unless Ship::FRAUD_VERDICTS.include?(params[:verdict].to_s)
    return stale unless @ship.awaiting_fraud?
    return taken if Claim.held_by_other?(@ship, "fraud", current_user)

    decided = case params[:verdict]
    when "pass" then @ship.pass_fraud!(by: current_user, notes: params[:fraud_notes])
    when "deduct" then @ship.pass_fraud!(by: current_user, deduction: params[:deduct_hours], notes: params[:fraud_notes])
    when "ban" then @ship.ban_for_fraud!(by: current_user, notes: params[:fraud_notes])
    end
    return refill unless decided

    @ship.claims.where(stage: "fraud").delete_all
    done(admin_fraud_path)
  end

  # A ship that waits for its fraud check goes back to review, with a reason.
  def send_back
    return stale unless @ship.awaiting_fraud?
    return taken if Claim.held_by_other?(@ship, "fraud", current_user)
    return refill unless @ship.send_back_to_review!(by: current_user, reason: params[:reason])

    @ship.claims.where(stage: "fraud").delete_all
    redirect_to admin_ship_path(@ship, queue: params[:queue].presence), notice: "Sent back to review."
  end

  # The title, description, what they changed and the links an admin corrects (Ship::Snapshot). The screenshots save
  # through Admin::ShipScreenshotsController. A field that fails its check comes back with what was typed.
  def snapshot
    @snapshot = Ship::Snapshot.new(@ship)
    return redirect_to(admin_ship_path(@ship), alert: "Someone else edits your own ship.") if @snapshot.own?(current_user)

    case @snapshot.update(params.fetch(:snapshot, {}).permit(*Ship::Snapshot::FIELDS), by: current_user)
    when true then redirect_to admin_ship_path(@ship), notice: "Snapshot saved."
    when nil then redirect_to admin_ship_path(@ship), notice: "Nothing changed."
    else
      load_review
      render :show, status: :unprocessable_entity
    end
  end

  # D-065: moves the moment the project's Hackatime time starts counting, or clears the reviewer's start (the later of
  # Save Point's start and the sign-up counts again). Logged like an admin tool call. Saving rebuilds their days.
  def hours_start
    project = @ship.project
    value = params[:clear].present? ? nil : parse_start(params[:hours_start_override])
    return redirect_to(admin_ship_path(@ship), alert: "Pick a date and time, or clear the override.") if value == :invalid
    return redirect_to(admin_ship_path(@ship), notice: "Nothing changed.") if project.hours_start_override == value

    AdminAuditEvent.create!(user: current_user, tool: "set_hours_start", ids: { "ship_id" => @ship.id, "project_id" => project.id })
    if project.update(hours_start_override: value)
      redirect_to admin_ship_path(@ship), notice: value ? "Hours now count from #{value.utc.strftime("%b %-d, %H:%M")} UTC." : "Override cleared."
    else
      redirect_to admin_ship_path(@ship), alert: project.errors.full_messages_for(:hours_start_override).first
    end
  end

  # D-085: how many of the ship's Lapse hours were coding. Saved on its own, so the review page draws again with the art cap
  # worked from it. Logged like an admin tool call.
  def lapse_split
    return redirect_to(admin_ship_path(@ship), alert: "This ship isn't in review.") unless @ship.in_review?

    if @ship.set_lapse_coding!(params[:lapse_coding_hours])
      AdminAuditEvent.create!(user: current_user, tool: "set_lapse_coding", ids: { "ship_id" => @ship.id })
      redirect_to admin_ship_path(@ship, queue: params[:queue].presence), notice: "Lapse coding set to #{Ship::Limits.hrs(@ship.lapse_coding_hours)}."
    else
      redirect_to admin_ship_path(@ship, queue: params[:queue].presence), alert: @ship.errors.messages_for(:lapse_coding_hours).first
    end
  end

  # D-102: the AI coding hours the reviewer sets above Hackatime's, with why. Saved on its own, like the Lapse split, so the
  # review page draws again with the coding maximum worked from it. A blank figure clears it. Logged like an admin tool call.
  def reviewer_ai
    return redirect_to(admin_ship_path(@ship), alert: "This ship isn't in review.") unless @ship.in_review?

    if @ship.set_reviewer_ai!(params[:reviewer_ai_coding_hours], params[:reviewer_ai_reason])
      AdminAuditEvent.create!(user: current_user, tool: "set_reviewer_ai", ids: { "ship_id" => @ship.id })
      notice = @ship.reviewer_ai_coding_hours ? "AI coding set to #{Ship::Limits.hrs(@ship.reviewer_ai_coding_hours)}." : "AI coding back to Hackatime's figure."
      redirect_to admin_ship_path(@ship, queue: params[:queue].presence), notice:
    else
      alert = @ship.errors.messages_for(:reviewer_ai_coding_hours).first || @ship.errors.messages_for(:reviewer_ai_reason).first
      redirect_to admin_ship_path(@ship, queue: params[:queue].presence), alert:
    end
  end

  # The checklist saves on every tick, while the ship is in review (D-049).
  def checklist
    return head(:unprocessable_entity) unless @ship.in_review?
    return head(:forbidden) if @ship.by?(current_user)

    @ship.update!(review_checklist: @ship.review_checklist.merge(params.require(:key) => params[:value] == "1"))
    head :no_content
  end

  private
    def set_ship = @ship = Ship.includes(:decided_by, :reviewer, :fraud_reviewer, project: :user).find(params[:id])

    def load_review
      review = @ship.review
      @others, @commits, @earlier_ship, @limits = review.others, review.commits, review.earlier_ship, review.limits
      # D-101: a later ship lists the commits since the last approved ship. `?commits=all` lists all since the hours start. The
      # evidence keeps the full result, since the release check needs the earliest commit.
      @earlier_approval = @ship.earlier_approval
      @all_commits = params[:commits] == "all"
      @listed_commits = @earlier_approval && !@all_commits ? @commits.since(@earlier_approval.ship.created_at) : @commits
      # D-126: the Hackatime time behind each commit, worked from the full list so a figure never lumps in commits that aren't shown.
      @commit_times = Ship::CommitTimes.for(@ship, @commits)
      @snapshot ||= Ship::Snapshot.new(@ship)
      @readme = Ship::Readme.for(@ship)
      # D-063: the evidence panels. Each part is looked up as the page draws it and shows its own problem line.
      @evidence = Ship::Evidence.new(@ship, commits: @commits)
      @send_backs = @ship.send_backs.includes(:user).to_a
      @claim, @held = claim_for_page
    end

    # Opening a ship that waits for someone takes the claim, unless another admin's is live (then the page says so, with a
    # button to take over). Your own ship has none: someone else judges it.
    def claim_for_page
      return [ nil, false ] unless @ship.pending? && !@ship.by?(current_user)

      claim, took = Claim.acquire(@ship, claim_stage, current_user, force: params[:take].present?)
      [ claim, !took ]
    end

    def claim_stage = @ship.in_review? ? "review" : "fraud"

    # Shows the page again with what the admin typed and what's missing.
    def refill
      load_review
      render :show, status: :unprocessable_entity
    end

    # Back to the next ship in the queue when this one came from it, else to this ship.
    def done(queue_path)
      redirect_to params[:queue].present? ? queue_path : admin_ship_path(@ship), notice: "Saved."
    end

    # The queues skip an admin's own ships, and a direct post can't judge one.
    def refuse_own_ship
      redirect_to admin_ship_path(@ship), alert: "Someone else judges your own ship." if @ship.by?(current_user)
    end

    # A datetime-local value is a UTC time here. nil for none, :invalid for what isn't one.
    def parse_start(text)
      return if text.blank?

      Time.find_zone!("UTC").parse(text.to_s) || :invalid
    rescue ArgumentError
      :invalid
    end

    def stale = redirect_to(admin_ship_path(@ship), alert: "That one's moved on already.")
    # D-109: the participant shipped again while this page was open, so this ship is out of the queue. The verdict is not applied.
    def replaced = redirect_to(admin_ship_path(@ship), alert: Ship::REPLACED_MESSAGE)
    def taken = redirect_to(admin_ship_path(@ship), alert: "Someone else holds this ship.")
end
