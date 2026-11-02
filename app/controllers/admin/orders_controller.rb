# Every prize claimed with approved hours (Order): waiting to be ordered first, oldest at the top, then ordered.
# Order it from where it says, then mark it ordered here; the bot tells them (OrderNotifier).
class Admin::OrdersController < Admin::BaseController
  def index
    @waiting = Order.waiting.includes(project: :user).order(:created_at)
    @ordered = Order.ordered.includes(:ordered_by, project: :user).order(ordered_at: :desc)
  end

  def update
    order = Order.find(params[:id])
    result = order.place!(by: current_user)
    return redirect_to admin_orders_path, alert: "That one's been #{order.stickers? ? "shipped" : "ordered"} already." unless result

    redirect_to admin_orders_path, notice: ("Shipped, but Theseus had it already, so there's no letter ID." if result == :already_sent)
  rescue TheseusClient::Error, Order::NotSent => e
    redirect_to admin_orders_path, alert: e.message
  end

  # Every waiting sticker order to Theseus (D-067), one at a time: a failure leaves that one waiting and goes on.
  def send_stickers
    sent = 0
    unknown = 0
    failed = []
    held = []
    Order.waiting.where(prize_key: Prize::STICKERS.key).includes(project: :user).order(:created_at).each do |order|
      result = order.place!(by: current_user)
      sent += 1 if result
      unknown += 1 if result == :already_sent
    rescue Order::NotSent => e
      held << "order #{order.id} (#{e.message.delete_prefix("Not sent: ")})"
    rescue TheseusClient::Error => e
      failed << "order #{order.id} (#{e.message})"
    end
    message = "Shipped #{sent} sticker #{"order".pluralize(sent)}."
    message += " #{unknown} had a letter already, so there's no letter ID." if unknown.positive?
    message += " Not sent, still waiting: #{held.join("; ")}." if held.any?
    flash[failed.any? || held.any? ? :alert : :notice] = failed.any? ? "#{message} Failed: #{failed.join("; ")}." : message
    redirect_to admin_orders_path
  end
end
