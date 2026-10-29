# The admin projects list (Admin::ProjectsController): its sortable column headers (D-114).
module Admin::ProjectsHelper
  SORT_LABELS = { "project" => "Project", "who" => "Who", "pledge" => "Pledge", "hackatime" => "Hackatime", "hours" => "Hours",
                  "streak" => "Streak", "buddy" => "Buddy", "ship" => "Ship" }.freeze

  # A column header that sorts the list by `key`: a link that keeps the search, opens the key's own direction first and
  # reverses it on a second click. The current sort shows its direction (an arrow, and aria-sort on the th).
  def sortable_header(key, sort:, dir:, query:, **options)
    current = sort == key
    to = current ? (dir == "asc" ? "desc" : "asc") : Project::ADMIN_SORT_DEFAULT_DIRECTIONS.fetch(key)
    label = SORT_LABELS.fetch(key)
    arrow = sp_icon(dir == "asc" ? "arrow-up-fill" : "arrow-down-fill", "pg-admin-projects__sort-arrow") if current
    link = link_to admin_projects_path(q: query.presence, sort: key, dir: to), class: "pg-admin-projects__sort", data: { sort: key } do
      safe_join([ label, arrow ].compact)
    end
    aria = current ? { sort: dir == "asc" ? "ascending" : "descending" } : {}
    tag.th(link, scope: "col", aria:, **options)
  end

  # "Newest first." or "Sorted by hours, descending. Newest first among equals." for the note under the title.
  def projects_order_note(sort, dir)
    return "Newest first." unless sort

    "Sorted by #{sort == "hackatime" ? "Hackatime" : SORT_LABELS.fetch(sort).downcase}, #{dir == "asc" ? "ascending" : "descending"}. Newest first among equals."
  end
end
