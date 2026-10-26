module AdminMcp::Tools::Projects
  # The projects page: every project, newest first, ?q= narrowing it.
  class FindProjects < AdminMcp::Tool
    reads "find_projects", "Find projects",
          "Every project, newest first, as the Projects page lists it: who pledged it, the goal, pace, Hackatime state, hours since Hackatime " \
          "started counting, streak, buddy and where its ships have got it. query narrows by the project's name or idea, or who it's by. " \
          "Answers { total, projects }.",
          { query: { type: "string", description: "Part of the project's name or idea, or the person's name, email or Slack display name." },
            **AdminMcp::Tool::PAGE }

    def self.run(args, _caller)
      projects = Project.includes(:user, :ships, pair_as_first: %i[first_project second_project], pair_as_second: %i[first_project second_project])
                        .order(created_at: :desc, id: :desc)
      projects = projects.search(args[:query].to_s.strip) if args[:query].present?
      total, rows = page(projects, args)
      # Everyone's hours in one query, not one each.
      seconds = StreakActivity.where(user_id: rows.map(&:user_id), activity_date: Program::FIRST_STREAK_DATE..).group(:user_id).sum(:coded_seconds)
      { total:, projects: rows.map { AdminMcp::Present.project(it, seconds: seconds.fetch(it.user_id, 0)) } }
    end
  end

  # One project in full, as the project page shows it.
  class GetProject < AdminMcp::Tool
    reads "get_project", "Get one project",
          "One project in full: its row, the pledge, hours, the schedule (day number, finish date, deadline), the days built, its ships " \
          "(use get_ship to open one), orders and extension.",
          { project_id: { type: "integer", description: "The project ID." } }, required: %w[project_id]

    def self.run(args, _caller)
      project = Project.includes(:user, :orders, :extension, ships: :decided_by).find(args[:project_id])
      user = project.user
      days = user.streak_activities.where(activity_date: Program::FIRST_STREAK_DATE.., coded_seconds: 1..).order(:activity_date)
      seconds = StreakActivity.where(user_id: user.id, activity_date: Program::FIRST_STREAK_DATE..).sum(:coded_seconds)
      AdminMcp::Present.project(project, seconds:).merge(
        hours_logged: project.hours_logged.to_f, hours_approved: project.hours_approved, hours_to_spend: project.hours_to_spend,
        day_number: project.day_number, finish_on: project.finish_on, deadline: project.deadline, timezone: user.timezone.presence || "UTC",
        hackatime_seen_count: project.hackatime_seen_count, hackatime_seen_hours: project.hackatime_seen_seconds&.then { (it / 3600.0).round(1) },
        hackatime_seen_at: project.hackatime_seen_at, hours_synced_at: user.streak_synced_at, repo_later: project.repo_later, has_screenshot: project.screenshot.attached?,
        slack_stopped_at: user.slack_muted_at, slack_dm_failed_at: user.slack_dm_failed_at,
        days_built: days.map { { date: it.activity_date, hours: (it.coded_seconds / 3600.0).round(1), counts_for_streak: it.completed? } },
        ships: project.ships.sort_by(&:created_at).reverse.map { AdminMcp::Present.ship(it) },
        orders: project.orders.map { { id: it.id, prize: it.configuration, status: it.status, hours: it.hours.to_f } },
        extension: (AdminMcp::Present.extension(project.extension) if project.extension)
      )
    end
  end
end
