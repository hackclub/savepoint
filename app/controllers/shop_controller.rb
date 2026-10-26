# The shop: every prize in Prize::ALL, fewest hours first, with your approved hours to spend on them (claiming is Order,
# through OrdersController). Anyone can look: without a project it's the public shop, every prize and what it takes.
class ShopController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  # Your hours, as of the last sync (a sync's queued if it's time); or, without a project, the public shop.
  def show
    @project = current_user&.project
    current_user.sync_streak_if_stale! if @project
    # The project page's "Claim your stickers" links here with ?claim=stickers: open the sticker sheet on its form (D-051),
    # but only while the stickers are still claimable.
    @open_sticker_claim = params[:claim] == "stickers" && helpers.shop_sticker_claim?(@project)
  end
end
