# The shapes the tools send, built from what the admin pages show and no more: a person with the details the people
# page lists, a project as the projects page lists it, a ship as the ships list does. Each names its records by ID, so
# a tool's answer stays small and a follow-up tool call can open any of them.
module AdminMcp::Present
  module_function

  # Who a row is about, as every admin list names them: the name, email and Slack display name.
  def user_ref(user)
    { id: user.id, name: user.name.presence || user.public_name, email: user.email, slack_display_name: user.slack_display_name.presence }
  end

  # A row of the people page.
  def person(user)
    project = user.project
    { **user_ref(user), hca_id: user.hca_id, slack_id: user.slack_id, admin: user.listed_admin?, current_streak: user.current_streak,
      signed_up_at: user.created_at, hours_synced_at: user.streak_synced_at, timezone: user.timezone,
      project: (project_brief(project) if project) }
  end

  def project_brief(project)
    { id: project.id, title: project.title, pace_minutes: project.pace_minutes, goal: project.chosen_prize&.name,
      hackatime: hackatime_state(project) }
  end

  def hackatime_state(project)
    return "tracking" if project.tracking?

    project.hackatime_linked? ? "linked, no project picked" : "not linked"
  end

  # A row of the projects page. `seconds` is the user's coded seconds since Hackatime started counting.
  def project(project, seconds: 0)
    user = project.user
    buddy = project.buddy
    { id: project.id, title: project.title, name: project.name, idea: project.idea, user: user_ref(user),
      goal: project.chosen_prize&.name, pace_minutes: project.pace_minutes, build_time: project.build_time, signed_on: project.signed_on,
      hackatime: hackatime_state(project), hackatime_projects: project.hackatime_projects, hackatime_auto_linked: project.hackatime_auto_linked,
      hours: (project.tracking? ? (seconds / 3600.0).round(1) : 0), streak: user.current_streak, repo_url: project.repo_url.presence,
      buddy: (buddy && { project_id: buddy.id, title: buddy.title }), buddy_skipped: project.buddy_skipped, buddy_invited: project.buddy_invited,
      ship: ship_state(project) }
  end

  # Where a project's ships have got it, as the projects page's last column says.
  def ship_state(project)
    return "in_review" if project.ship_in_review
    return "approved" if project.shipped?

    return "rejected" if project.ship_rejected

    project.ships.any? ? "changes_needed" : "none"
  end

  # A row of the ships list.
  def ship(ship)
    project = ship.project
    { id: ship.id, project_id: project.id, title: ship.title, user: user_ref(project.user), hackatime_projects: ship.hackatime_projects,
      hours: ship.hours.to_f, shipped_at: ship.created_at, status: ship.status, status_label: Admin::ShipsHelper::SHIP_STATUS_LABELS.fetch(ship.status), fraud_status: ship.fraud_status,
      decided_by: ship.decided_by&.first_name, decided_at: ship.decided_at }
  end

  # D-063: the review page's evidence panels (Ship::Evidence), as get_ship answers them.
  def evidence(evidence, limits)
    hackatime, repo, lapses, stardance, user = evidence.hackatime, evidence.repo, evidence.lapses, evidence.stardance, evidence.user
    release = repo.release
    art_share = (limits.art * 100 / limits.claimed).round(1).to_f if limits.art_known? && limits.claimed.positive?
    {
      hackatime_projects: { captured_at_ship: hackatime.captured, problem: hackatime.problem,
                            list: hackatime.rows.map { { name: it.name, seconds_at_ship: it.at_ship, seconds_now: it.now } } },
      repo: { status: repo.status, message: repo.message, full_name: repo.full_name, commits: repo.commits, last_push: repo.pushed_at,
              stars: repo.stars, release_predates_start_or_first_commit: evidence.release_predates?,
              release: (release && { tag: release.tag, url: release.url, published_at: release.published_at,
                                     files: release.assets.map { { name: it.name, bytes: it.size } } }) },
      lapses: { error: lapses.error, art_share_percent: art_share,
                art_cap_percent: Ship::Limits::ART_CAP_PERCENT,
                sessions: lapses.lapses.map { { id: it.id, title: it.title, seconds: it.duration, project: it.project, url: it.url } } },
      participant: { name: user.name, email: user.email, slack_id: user.slack_id, verification_status: user.verification_status,
                     ysws_eligible: user.ysws_eligible?, hackatime_uid: user.hackatime_uid, hackatime_trust_level: evidence.trust_level,
                     other_ships: evidence.other_ships.map { { id: it.id, title: it.title, status: it.status, hours: it.hours.to_f } } },
      same_repo_or_person: evidence.duplicates.map { { user_id: it.user.id, name: it.user.name, reason: it.reason } },
      stardance: { status: stardance.status, project_ids: stardance.ids },
      links: { telescreen: evidence.telescreen_url, lapse_review: evidence.lapse_review_url }
    }
  end

  def limits(limits)
    { hackatime_counted: limits.claimed.to_f, ai_coding: limits.ai_coding.to_f, ai_known: limits.ai_known?, ai_cut: limits.ai_cut.to_f,
      art: limits.art.to_f, art_known: limits.art_known?, art_cut: limits.art_cut.to_f, art_cap_percent: Ship::Limits::ART_CAP_PERCENT,
      most_to_approve: limits.most.to_f, cut: limits.cut?, reason: limits.reason }
  end

  # A row of the orders page. The address and phone are what the page shows next to a prize to order, so a waiting order has
  # them and an ordered one does not (it's posted).
  def order(order)
    user = order.project.user
    row = { id: order.id, project_id: order.project_id, user: user_ref(user), prize: order.configuration, prize_key: order.prize_key,
            kind: order.prize_item&.kind, hours: order.hours.to_f, status: order.status, claimed_at: order.created_at,
            ordered_by: order.ordered_by&.first_name, ordered_at: order.ordered_at, theseus_letter_id: order.theseus_letter_id }
    return row unless order.waiting?

    phone = order.address.is_a?(Hash) ? order.address["phone_number"] : nil
    row.merge(recipient: order.recipient_name.presence || user.name.presence || user.public_name,
              address: user.address_lines(order.address), phone: phone.presence)
  end

  def extension(extension)
    { id: extension.id, project_id: extension.project_id, user: user_ref(extension.project.user), project: extension.project.title,
      reason: extension.reason, status: extension.status, asked_at: extension.created_at, decided_by: extension.decided_by&.first_name,
      decided_at: extension.decided_at }
  end
end
