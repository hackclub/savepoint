# A ship's screenshots, edited from its admin page (Ship::Snapshot): add, replace, remove and reorder, each saved at once
# and answered in JSON for ship_screenshots_controller.js. Only the ship changes. An admin can't edit their own ship.
class Admin::ShipScreenshotsController < Admin::BaseController
  before_action :set_ship
  before_action :refuse_own_ship

  rescue_from Ship::Snapshot::Refused do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  # A new screenshot at the end, or with `replace` (an id) in that one's place.
  def create
    attachment = @snapshot.add_screenshot(params[:screenshot], by: current_user, replace: params[:replace])
    render json: { id: attachment.id.to_s, url: rails_storage_redirect_path(attachment) }, status: :created
  end

  def destroy
    @snapshot.remove_screenshot(params[:id], by: current_user)
    head :no_content
  end

  def order
    @snapshot.order_screenshots(params[:ids], by: current_user)
    head :no_content
  end

  private
    def set_ship
      @ship = Ship.find(params[:ship_id])
      @snapshot = Ship::Snapshot.new(@ship)
    end

    def refuse_own_ship
      render json: { error: "Someone else edits your own ship." }, status: :forbidden if @snapshot.own?(current_user)
    end
end
