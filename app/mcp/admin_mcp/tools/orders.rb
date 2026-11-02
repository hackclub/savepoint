module AdminMcp::Tools::Orders
  # The Orders page: prizes claimed with approved hours, waiting to be ordered first.
  class ListOrders < AdminMcp::Tool
    reads "list_orders", "List prize orders",
          "Every prize claimed with approved hours: who, what, the hours, and when. Waiting orders come with the recipient, address and phone to order to " \
          "(as the Orders page shows), oldest first. Ordered ones show who ordered them, newest first. Answers { total, orders }.",
          { status: { type: "string", enum: %w[waiting ordered all], description: "Default waiting." }, **AdminMcp::Tool::PAGE }

    def self.run(args, _caller)
      status = args[:status] || "waiting"
      orders = Order.includes(:ordered_by, project: :user)
      orders = case status
      when "waiting" then orders.waiting.order(:created_at, :id)
      when "ordered" then orders.ordered.order(ordered_at: :desc, id: :desc)
      else orders.order(Arel.sql("status = 'waiting' desc"), :created_at, :id)
      end
      total, rows = page(orders, args)
      { total:, orders: rows.map { AdminMcp::Present.order(it) } }
    end
  end

  class MarkOrderOrdered < AdminMcp::Tool
    writes "mark_order_ordered", "Mark an order as ordered",
           "Marks a waiting prize order as ordered, once you've ordered it (the Orders page's Mark ordered button). The bot DMs the participant on Slack. " \
           "A sticker order is shipped through Theseus first (D-067) and only then marked ordered, so it can't be marked without being shipped; " \
           "if Theseus refuses it, or Hackatime has banned the account or it isn't YSWS-eligible (rechecked just before sending), the order stays waiting and the reason comes back. Answers { ordered }: false when it was ordered already.",
           { order_id: { type: "integer", description: "The order ID, from list_orders." } }, required: %w[order_id]

    def self.run(args, caller)
      order = Order.find(args[:order_id])
      result = order.place!(by: caller.user)
      message = if !result then "That one's been #{order.stickers? ? "shipped" : "ordered"} already."
      elsif result == :already_sent then "Theseus had a letter for it already, so there's no letter ID."
      end
      { ordered: !!result, message:, order: AdminMcp::Present.order(order.reload) }
    rescue TheseusClient::Error, Order::NotSent => e
      { ordered: false, message: e.message, order: AdminMcp::Present.order(order.reload) }
    end
  end
end
