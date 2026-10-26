# The admin pages, in one list: the nav above each of them (admin/_nav) and the admin home (/admin) both read it.
# The ones with something waiting on an admin come first.
module Admin::NavHelper
  def admin_pages
    [
      { label: "Orders", path: admin_orders_path, about: "Prizes claimed with approved hours, to order and mark ordered." },
      { label: "Ships", path: admin_ships_path, about: "Every ship in full, screenshot and all, to approve or send back." },
      { label: "Extensions", path: admin_extensions_path, about: "Who's asked for more time to ship, and why." },
      { label: "Projects", path: admin_projects_path, about: "Every project, searchable, and each in full." },
      { label: "People", path: admin_users_path, about: "Everyone who's signed in, and seeing the site as any of them." },
      { label: "Numbers", path: admin_metrics_path, about: "Save Point's numbers, day by day." },
      { label: "Stats", path: admin_stats_path, about: "The stats page everyone sees: totals, the funnel and who's building each day." },
      { label: "Bandit", path: admin_nudges_path, about: "How the Slack nudges are doing, and what the bandit's learned." },
      { label: "Tokens", path: admin_tokens_path, about: "Your tokens for the admin MCP server, so Claude can do admin work and read the analytics." },
      # Not a Rails route: an Orchard ingress sends /admin/insights to the analytics service (D-040). So it's a plain
      # path, and a full page load, not a Turbo visit.
      { label: "Insights", path: "/admin/insights/", external: true, about: "Where visitors come from and what they do, in the analytics service." }
    ]
  end

  # What a count on the admin home means, for the page it's on.
  def admin_waiting_label(label)
    { "Orders" => "to order", "Ships" => "in review" }.fetch(label, "waiting")
  end
end
