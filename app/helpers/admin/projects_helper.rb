# The admin projects list (Admin::ProjectsController): its sortable column headers (D-114).
module Admin::ProjectsHelper
  SORT_LABELS = { "project" => "Project", "who" => "Who", "pledge" => "Pledge", "hackatime" => "Hackatime", "hours" => "Hours",
                  "streak" => "Streak", "buddy" => "Buddy", "ship" => "Ship", "jame_gam" => "Jame gam" }.freeze

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

  # D-121, D-122: the jame gam cell, for this game's submissions only. The status word in a danger chip when any is not Approved
  # ("Pending", "no status yet", or "2 not approved" when there are several), then "of M"; "M, all approved" otherwise; a dash
  # with none. The words carry the meaning, not only the colour. Read from the stored submissions, so it is right before the sweep
  # recounts the columns.
  def jame_gam_summary(project)
    total = project.jame_gam_match_count
    unapproved = project.jame_gam_submissions.count { it["matches"] && JameGam.flagged?(it["review_status"]) }
    if total.zero?
      tag.span("—", class: "pg-admin-projects__muted")
    elsif unapproved.positive?
      label = unapproved == 1 ? JameGam.unapproved_statuses(project.jame_gam_submissions).first.presence || "no status yet" : "#{unapproved} not approved"
      tag.span(label, class: "pg-admin-projects__jame pg-admin-projects__jame--flagged") + " of #{total}"
    else
      "#{total}, all approved"
    end
  end

  # "Newest first." or "Sorted by hours, descending. Newest first among equals." for the note under the title.
  def projects_order_note(sort, dir)
    return "Newest first." unless sort

    "Sorted by #{sort == "hackatime" ? "Hackatime" : SORT_LABELS.fetch(sort).downcase}, #{dir == "asc" ? "ascending" : "descending"}. Newest first among equals."
  end
end
