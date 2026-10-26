# The review page calls this every 30 seconds to keep its admin's claim on the ship alive. If another admin has taken it
# over, the answer says who, and the page shows its banner instead of letting this one keep typing into a lost claim.
class Admin::ClaimsController < Admin::BaseController
  def heartbeat
    ship = Ship.find(params[:id])
    return head(:forbidden) if ship.by?(current_user) || !params[:stage].in?(Claim::STAGES)

    claim, took = Claim.acquire(ship, params[:stage], current_user, force: params[:force].present?)
    render json: { ok: took, holder: claim.user.first_name.presence || "Someone" }
  end
end
