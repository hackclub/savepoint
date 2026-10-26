# Spending approved hours on a prize (Order), from the shop: any prize they cover. The admins hear on Slack and order it
# from /admin/orders. Back to the shop either way, with what it says. The claim sheet sends the name for the parcel with
# it: it becomes their preferred name (nil when blank or the Hack Club name) and the order keeps it as it was then, with the
# address they confirmed beside it (ShippingAddress, D-024).
class OrdersController < ApplicationController
  before_action :require_project

  BANNED = "This account can't claim prizes.".freeze

  def create
    return refuse(BANNED) if current_user.banned?

    order = @project.orders.build(order_params)
    # The address they confirmed in the claim step, else (a claim with no form) the one Hack Club Auth shared. Never logged.
    shipping = params.key?(:address) ? ShippingAddress.from_params(params[:address]) : ShippingAddress.for(current_user)
    problems = shipping.problems
    return refuse(problems.values.first, problems) if problems.any?

    order.address = shipping.to_h
    if params.key?(:preferred_name)
      name = parcel_name
      current_user.preferred_name = name
      order.recipient_name = name || current_user.name
    end
    unless current_user.valid? && order.save
      name_problem = current_user.errors.full_messages_for(:preferred_name).first
      return refuse(name_problem || order.problem, preferred_name: name_problem)
    end
    current_user.save! if current_user.changed?

    OrderNotifier.claimed(order)

    flash[:shop_claimed] = order.prize_key
    respond_to do |format|
      format.html { redirect_to shop_path }
      format.json { render json: { redirect: shop_path } }
    end
  end

  private
    # The claim step sends its form with fetch (prize_sheet_controller.js) and shows each field's problem under it. Without
    # JavaScript, the shop says the first one.
    def refuse(message, fields = {})
      respond_to do |format|
        format.html { redirect_to shop_path, flash: { shop_error: message } }
        format.json { render json: { message:, fields: fields.compact }, status: :unprocessable_content }
      end
    end

    def require_project
      @project = current_user&.project
      redirect_to onboarding_path unless @project
    end

    # The name asked for, tidied like User#preferred_name, or nil when blank or just their Hack Club name.
    def parcel_name
      name = User.normalize_value_for(:preferred_name, params[:preferred_name].to_s)
      name unless name == current_user.name
    end

    def order_params
      params.expect(order: [ :prize_key ])
    end
end
