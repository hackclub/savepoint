# Rapid-fire review (D-063): /admin/review and /admin/fraud open the oldest ship waiting for that stage. "Next" skips
# the ships another admin holds, the ones this admin skipped this session (n), and this admin's own.
class Admin::QueuesController < Admin::BaseController
  def review = next_in(Ship.reviewable.order(:created_at, :id), "review")
  def fraud = next_in(Ship.awaiting_fraud.order(:reviewed_at, :id), "fraud")

  private
    def next_in(scope, stage)
      skipped = (session[:skipped_ships] ||= {})[stage] ||= []
      skipped.clear if params[:reset]
      skipped << params[:skip].to_i if params[:skip].present?
      skipped.uniq!
      held = Claim.live.where(stage:).where.not(user: current_user).select(:ship_id)
      mine = Project.where(user: current_user).select(:id)
      ship = scope.where.not(id: held).where.not(id: skipped).where.not(project_id: mine).first
      return redirect_to(admin_ship_path(ship, queue: 1)) if ship

      @stage = stage
      @left = scope.count
      @skipped = skipped.size
      render :empty
    end
end
