# The icon for each admin page (Admin::NavHelper#admin_pages), in the admin nav (admin/_nav) and on the admin home's
# tiles and table (admin/home/show).
module AdminHomePageHelper
  ADMIN_PAGE_ICONS = {
    "Admin" => "home-4-fill", "Orders" => "truck-fill", "Ships" => "rocket-fill", "Extensions" => "time-fill",
    "Projects" => "game-2-fill", "People" => "user-3-fill",
    "Bandit" => "sparkles-fill", "Tokens" => "lock-fill", "Insights" => "search-fill"
  }.freeze

  def admin_page_icon(label) = sp_icon(ADMIN_PAGE_ICONS.fetch(label, "right-fill"))
end
