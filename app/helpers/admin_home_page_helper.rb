# The icon for each admin page (Admin::NavHelper#admin_pages), in the admin nav (admin/_nav) and on the admin home's
# tiles and table (admin/home/show).
module AdminHomePageHelper
  ADMIN_PAGE_ICONS = {
    "Admin" => "home-4-fill", "Orders" => "truck-fill", "Ships" => "rocket-fill", "Extensions" => "time-fill",
    "Projects" => "game-2-fill", "People" => "user-3-fill",
    "Bandit" => "sparkles-fill", "Tokens" => "lock-fill", "Insights" => "search-fill"
  }.freeze

  # An average of seconds as "42s" or "1m 05s"; "—" when there is none (a question nobody identified has no average).
  def faq_average_time(seconds)
    return "—" unless seconds

    whole = seconds.round
    whole < 60 ? "#{whole}s" : format("%dm %02ds", *whole.divmod(60))
  end

  def admin_page_icon(label) = sp_icon(ADMIN_PAGE_ICONS.fetch(label, "right-fill"))
end
