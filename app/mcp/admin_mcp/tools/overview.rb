module AdminMcp::Tools::Overview
  # What the admin home shows: what's waiting on an admin, then the numbers beside it.
  class AdminSummary < AdminMcp::Tool
    reads "admin_summary", "What is waiting on an admin",
          "What the admin home shows: orders to order, ships in review and extensions waiting, then sign-ups, daily active builders, " \
          "hours built but not shipped, hours in review and hours approved (participants only, admins left out)."

    def self.run(_args, _caller)
      { waiting: { orders: Order.waiting.count, ships_in_review: Ship.in_review.count, ships_awaiting_fraud: Ship.awaiting_fraud.count, extensions: Extension.pending.count },
        totals: { projects: Project.count, people: User.count }, summary: ::AdminSummary.cached }
    end
  end
end
