module AdminMcp::Tools::People
  # The people page: everyone who's signed in, newest first, ?q= narrowing it.
  class FindPeople < AdminMcp::Tool
    reads "find_people", "Find people",
          "Everyone who's signed in, newest first, as the People page lists them: name, email, Slack and Hack Club IDs, streak, and their " \
          "project's pace, goal and Hackatime state. query narrows by name, email, Slack display name, Slack ID or Hack Club ID. " \
          "Answers { total, people }.",
          { query: { type: "string", description: "Part of a name, email, Slack display name, Slack ID or Hack Club ID." }, **AdminMcp::Tool::PAGE }

    def self.run(args, _caller)
      users = User.includes(:project).order(created_at: :desc, id: :desc)
      users = users.search(args[:query].to_s.strip) if args[:query].present?
      total, rows = page(users, args)
      { total:, people: rows.map { AdminMcp::Present.person(it) } }
    end
  end

  # One person, with what the people and project pages show about them.
  class GetPerson < AdminMcp::Tool
    reads "get_person", "Get one person",
          "One person: the People page's row, plus their project's ID, their ships (ID, status, hours), orders and extension, and whether " \
          "they stopped the bot's Slack messages or a DM failed.",
          { user_id: { type: "integer", description: "The user ID." } }, required: %w[user_id]

    def self.run(args, _caller)
      user = User.includes(project: %i[ships orders extension]).find(args[:user_id])
      project = user.project
      AdminMcp::Present.person(user).merge(
        slack_stopped_at: user.slack_muted_at, slack_dm_failed_at: user.slack_dm_failed_at,
        ships: (project&.ships&.sort_by(&:created_at)&.reverse || []).map { { id: it.id, status: it.status, hours: it.hours.to_f, shipped_at: it.created_at } },
        orders: (project&.orders || []).map { { id: it.id, prize: it.configuration, status: it.status, hours: it.hours.to_f } },
        extension: (AdminMcp::Present.extension(project.extension) if project&.extension)
      )
    end
  end
end
