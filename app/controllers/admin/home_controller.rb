# The admin home (/admin): what's waiting on an admin, and every admin page with what it's for (Admin::NavHelper).
class Admin::HomeController < Admin::BaseController
  def show
    @waiting = { "Orders" => Order.waiting.count, "Ships" => Ship.pending.count, "Extensions" => Extension.pending.count }
    @summary = AdminSummary.cached
    @totals = { "Projects" => Project.count, "People" => User.count }
  end
end
