module AdminMcp::Tools::Projects
  # The projects page: every project, newest first, ?q= narrowing it.
  class FindProjects < AdminMcp::Tool
    reads "find_projects", "Find projects",
          "Every project, newest first, as the Projects page lists it: who pledged it, the goal, pace, Hackatime state, hours since Hackatime " \
          "started counting, streak, buddy, where its ships have got it, party_queued (in the play party queue) and play_url (its latest ship's demo link). " \
          "query narrows by the project's name or idea, or who it's by. party_queued true returns only the play party queue, false only the rest. " \
          "Answers { total, projects }.",
          { query: { type: "string", description: "Part of the project's name or idea, or the person's name, email or Slack display name." },
            party_queued: { type: "boolean", description: "True for only the projects in the play party queue, false for only those not in it." },
            **AdminMcp::Tool::PAGE }

    def self.run(args, _caller)
      projects = Project.includes(:user, :ships, pair_as_first: %i[first_project second_project], pair_as_second: %i[first_project second_project])
                        .order(created_at: :desc, id: :desc)
      projects = projects.search(args[:query].to_s.strip) if args[:query].present?
      projects = projects.where(party_queued: args[:party_queued]) unless args[:party_queued].nil?
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
        shop_hours_credit: project.shop_hours_credit.to_f, shop_hours_credit_reason: project.shop_hours_credit_reason,
        shop_hours_credit_by: (User.find_by(id: project.shop_hours_credit_by_id)&.name if project.shop_hours_credit_by_id),
        shop_until: project.shop_until, shop_until_reason: project.shop_until_reason, shop_closes_at: project.shop_closes_at,
        day_number: project.day_number, finish_on: project.finish_on, deadline: project.deadline, timezone: UserTimezone.name(user.timezone),
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

  # D-155: a private ship window for one project. No DM, no post: the admin tells the person.
  class SetShipUntil < AdminMcp::Tool
    writes "set_ship_until", "Give one project a private ship window",
           "Gives one project a private window to ship after the public end (D-155): the project may ship until ship_until, and only Hackatime time from before the public end (Program::ENDS_AT) counts on that ship. " \
           "Send user_id or project_id, and ship_until as a UTC date and time like 2026-11-06T21:00, or null to clear it. It never shortens the public end or a Changes needed window, and an unset project is unchanged. " \
           "Sends no DM and posts nothing: tell the person yourself. Answers { project_id, user_id, ship_until, ship_closes_at }.",
           { user_id: { type: "integer", description: "The participant's user ID. Use this or project_id." },
             project_id: { type: "integer", description: "The project ID. Use this or user_id." },
             ship_until: { type: %w[string null], description: "A UTC date and time, or null to clear the window." } },
           required: %w[ship_until]

    def self.audit_extra(args)
      project = find_project(args)
      project ? { "project_id" => project.id } : {}
    rescue StandardError
      {}
    end

    def self.run(args, _caller)
      raise AdminMcp::Refused, "Send ship_until: a UTC date and time, or null to clear it." unless args.key?(:ship_until)

      project = find_project(args) || raise(AdminMcp::Refused, "Send user_id or project_id of a project that exists.")
      value = args[:ship_until].nil? ? nil : parse_time(args[:ship_until])
      raise AdminMcp::Refused, "Send ship_until as a UTC date and time like 2026-11-06T21:00, or null." if value == :invalid

      project.update!(ship_until: value)
      { project_id: project.id, user_id: project.user_id, ship_until: project.ship_until, ship_closes_at: project.ship_closes_at }
    end

    def self.find_project(args)
      if args[:project_id] then Project.find_by(id: args[:project_id])
      elsif args[:user_id] then Project.find_by(user_id: args[:user_id])
      end
    end

    def self.parse_time(text)
      return :invalid if text.blank?

      Time.find_zone!("UTC").parse(text.to_s) || :invalid
    rescue ArgumentError
      :invalid
    end
  end

  # D-158: a later shop close for one project. No DM, no post: the admin tells the person.
  class SetShopUntil < AdminMcp::Tool
    writes "set_shop_until", "Extend the shop for one project",
           "Gives one project a later shop close than the public one (Program::SHOP_CLOSES_AT, D-138): they can claim prizes with their spendable hours until `until` (D-158). " \
           "Send user_id or project_id, `until` as a UTC date and time like 2026-11-10T21:00 or null to clear it, and a reason. It never shortens the public close, and everyone else's shop is unchanged. " \
           "Sends no DM and posts nothing: tell the person yourself. Answers { project_id, user_id, shop_until, shop_closes_at }.",
           { user_id: { type: "integer", description: "The participant's user ID. Use this or project_id." },
             project_id: { type: "integer", description: "The project ID. Use this or user_id." },
             until: { type: %w[string null], description: "A UTC date and time, or null to clear the extension." },
             reason: { type: "string", description: "Why, in a sentence. Saved on the project. Not needed to clear." } },
           required: %w[until]

    def self.audit_extra(args)
      project = SetShipUntil.find_project(args)
      project ? { "project_id" => project.id, "old_shop_until" => project.shop_until&.iso8601, "new_shop_until" => args[:until].to_s.presence } : {}
    rescue StandardError
      {}
    end

    def self.run(args, _caller)
      raise AdminMcp::Refused, "Send until: a UTC date and time, or null to clear it." unless args.key?(:until)

      project = SetShipUntil.find_project(args) || raise(AdminMcp::Refused, "Send user_id or project_id of a project that exists.")
      if args[:until].nil?
        project.update!(shop_until: nil, shop_until_reason: nil)
      else
        value = SetShipUntil.parse_time(args[:until])
        raise AdminMcp::Refused, "Send until as a UTC date and time like 2026-11-10T21:00, or null." if value == :invalid
        raise AdminMcp::Refused, "Send a reason." if args[:reason].to_s.strip.blank?

        project.update!(shop_until: value, shop_until_reason: args[:reason].to_s.strip)
      end
      { project_id: project.id, user_id: project.user_id, shop_until: project.shop_until, shop_closes_at: project.shop_closes_at }
    end
  end

  # D-157: shop hours for one person. It adds to what they can spend and changes no ship, approved hours or Unified row.
  class CreditShopHours < AdminMcp::Tool
    MAX_PER_CALL = 2.0
    MAX_TOTAL = 5.0

    writes "credit_shop_hours", "Credit shop hours to one project",
           "Adds hours to what one person can spend in the shop (D-157). It changes no ship, no approved hours, no Hackatime hours and nothing sent to Airtable or the Unified YSWS DB. " \
           "Send user_id or project_id, hours (more than 0, at most #{MAX_PER_CALL} a call, #{MAX_TOTAL} in all for the project) and a reason. The hours add to any earlier credit. " \
           "Sends no DM and posts nothing: tell the person yourself. The audit row holds the old and new credit. Answers { project_id, user_id, shop_hours_credit, hours_to_spend }.",
           { user_id: { type: "integer", description: "The participant's user ID. Use this or project_id." },
             project_id: { type: "integer", description: "The project ID. Use this or user_id." },
             hours: { type: "number", description: "Hours to add, above 0 and at most #{MAX_PER_CALL}." },
             reason: { type: "string", description: "Why, in a sentence. Saved on the project." } },
           required: %w[hours reason]

    def self.audit_extra(args)
      project = find_project(args)
      return {} unless project

      old = project.shop_hours_credit.to_f
      { "project_id" => project.id, "old_credit" => old, "new_credit" => (old + args[:hours].to_f).round(2) }
    rescue StandardError
      {}
    end

    def self.run(args, caller)
      project = find_project(args) || raise(AdminMcp::Refused, "Send user_id or project_id of a project that exists.")
      hours = args[:hours]
      raise AdminMcp::Refused, "Send hours as a number above 0 and at most #{MAX_PER_CALL}." unless hours.is_a?(Numeric) && hours.positive? && hours <= MAX_PER_CALL
      raise AdminMcp::Refused, "Send a reason." if args[:reason].to_s.strip.blank?

      project.with_lock do
        total = (project.shop_hours_credit.to_f + hours).round(2)
        raise AdminMcp::Refused, "That would make #{total} credited hours; the most is #{MAX_TOTAL}." if total > MAX_TOTAL

        project.update!(shop_hours_credit: total, shop_hours_credit_reason: args[:reason].to_s.strip, shop_hours_credit_by_id: caller.user.id)
      end
      { project_id: project.id, user_id: project.user_id, shop_hours_credit: project.shop_hours_credit.to_f, hours_to_spend: project.hours_to_spend }
    end

    def self.find_project(args)
      if args[:project_id] then Project.find_by(id: args[:project_id])
      elsif args[:user_id] then Project.find_by(user_id: args[:user_id])
      end
    end
  end
end
