module ProjectsHelper
  PACE_LABELS = { 20 => "20 min", 45 => "45 min", 60 => "1 hr", 120 => "2 hrs", 180 => "3 hrs" }.freeze
  BUILD_TIME_LABELS = { "after school" => "after school", "evening" => "evenings", "late night" => "late nights",
                        "weekends" => "weekends" }.freeze
  # When today's session is, by when you build.
  BUILD_TIME_SOON = { "after school" => "after school", "evening" => "this evening", "late night" => "tonight",
                      "weekends" => "today" }.freeze

  # "Aseprite"
  def project_prize_name(project)
    project.chosen_prize&.name || project.prize_key.to_s
  end

  # "1.5 of 12 hrs": the hours your pick takes (Project#hours_needed).
  def project_hours_label(project, hours = project.hours_logged)
    "#{project_hours(hours)} of #{project_hours(project.hours_needed)} hrs"
  end

  # 1.5, or 2 rather than 2.0
  def project_hours(hours)
    hours.to_s.delete_suffix(".0")
  end

  # "Oct 15"
  def project_date(date)
    date.strftime("%b %-d")
  end

  # "45 min", "1 hr", or for a pace of "Just enough" and the like "52 min", "1 hr 15 min"
  def project_pace_label(minutes)
    PACE_LABELS.fetch(minutes) { minutes < 60 ? "#{minutes} min" : [ "#{minutes / 60} hr", ("#{minutes % 60} min" if minutes % 60 > 0) ].compact.join(" ") }
  end

  # The pace line on a prize tag in the project's picker: the minutes a day it still takes you to earn the prize's
  # hours from now to the end (your logged hours counted), or "Earned" when you've logged enough already.
  def project_prize_pace(project, prize)
    to_go = prize.hours - project.hours_unspent_logged
    to_go.positive? ? pace_html(Prize.pace_minutes(to_go)) : "Earned"
  end

  # "12 hrs · 45 min a day · done by Oct 15 · Aseprite"
  def project_meta(project)
    per = project.build_time == "weekends" ? "a session" : "a day"
    [ "#{project_hours(project.hours_needed)} hrs", "#{project_pace_label(project.pace_minutes)} #{per}",
      "done by #{project_date(project.finish_on)}", project.prize_configuration ].join(" · ")
  end

  # Your hours always come through Hackatime, from its plugin in the editor or engine you build your game in.
  def project_hackatime_how(project)
    "Install Hackatime in the editor or engine you build your game in. That's where your hours come from."
  end

  # How to get your first time onto Hackatime while there's nothing there to pick.
  # Until the editor has sent any time, say what the plugin is and link its setup.
  def project_first_time_how(project)
    return "Work on your game with Hackatime on. It shows up here and links itself." if project.hackatime_seen_seconds.to_i.positive?

    safe_join([
      "Hackatime hasn't seen any coding from you yet. It counts time through a plugin in the editor you build your game in. ",
      link_to("Set it up in your editor", hackatime_url, target: "_blank", rel: "noopener"),
      ". Then your project shows up here and links itself."
    ])
  end

  # "Don't see it?" for the Hackatime projects dropdown.
  def project_hackatime_refresh_hint(project)
    "Don't see it? Work on your game with Hackatime on, then refresh."
  end

  # D-064: a project that Hackatime links to another repo than this project's goes last, with `other_repo` set for the
  # warning line. It stays pickable, and a linked one stays ticked.
  def project_hackatime_choices(project, refresh: false)
    projects = Hackatime.pickable_projects(project.user, refresh:, since: project.hours_start)
    missing = project.hackatime_projects - projects.map(&:name)
    hours = ->(hackatime) { "#{hackatime.hours.to_s.delete_suffix(".0")} hrs" }
    known = missing.any? ? Hackatime.projects(project.user).index_by(&:name) : {}
    choices = missing.map { |name| { name:, note: known[name] ? hours.(known[name]) : "not on Hackatime now", linked: true } } +
      projects.map do |hackatime|
        { name: hackatime.name, note: hours.(hackatime), linked: project.hackatime_projects.include?(hackatime.name),
          earlier: project_earlier_label(hackatime, project.hours_start_source) }
      end
    repos = project.hackatime_repo_links
    choices = choices.map { |choice| choice.merge(other_repo: project.other_repo?(choice[:name], repos)) }
    { projects: choices.partition { |choice| !choice[:other_repo] }.flatten }
  rescue Hackatime::NotLinked, Hackatime::Expired
    { projects: [], problem: "Your Hackatime link expired.", relink: true }
  rescue Hackatime::Unavailable
    { projects: [], problem: "Couldn't reach Hackatime just now. Try refreshing." }
  end

  # D-089: "12 hrs before Save Point", the time on a Hackatime project that never counts, or nil when there's none. Someone
  # who joined after the launch (or whose start a reviewer moved) hasn't "before Save Point" to go by, so it says "before
  # your start".
  def project_earlier_label(hackatime, source)
    return unless hackatime.earlier_seconds.positive?

    "#{project_hours(hackatime.earlier_hours)} hrs before #{source == :launch ? "Save Point" : "your start"}"
  end

  # D-089: the line above the picker.
  def project_hackatime_pick_intro(start)
    "Pick your game, even if you've worked on it before. Only time from #{project_date(start)} on counts."
  end

  # "Link project", "Link 2 projects", or "Pick a project" with none ticked.
  def project_hackatime_link_label(count)
    count.zero? ? "Pick a project" : "Link #{count == 1 ? "project" : "#{count} projects"}"
  end

  # The setup card's one line: what's put off, or that setup's done.
  def project_setup_summary(project, step)
    if project.repo_put_off? then "Git repo put off"
    else
      left = project.optional_steps_left
      left.positive? ? "Setup done · #{pluralize(left, "optional step")} left" : "Setup done"
    end
  end

  # The setup steps as the page shows them. The one you're on (the step you picked, if you can still do it, or the
  # first one left) opens to show how to do it. Picking your Hackatime project waits its turn while there's nothing on
  # Hackatime to pick (it links itself once there is), but stays open too, so how to get that first time there (log some
  # code) is in view.
  def project_steps(project, step: nil)
    current = project.step_open?(step.to_s) ? step.to_s : Project::SETUP_STEPS.find { |key| !project.step_settled?(key) && !project.step_locked?(key) }
    Project::SETUP_STEPS.map do |key|
      # A step you reopen (the repo you'd put off) reads as still to do.
      settled = project.step_done?(key) && key != current
      # Put off (the repo said "later", the buddy skipped) isn't done: it keeps its note but gets no green check.
      later = settled && ((key == "repo" && project.repo_url.blank?) || (key == "buddy" && project.buddy.nil?))
      done = settled && !later
      title, note = project_step_label(project, key, settled)
      waiting = key == "hackatime_project" && project.waiting_for_hackatime_project? && project.hackatime_projects.none?
      { key:, number: Project::SETUP_STEPS.index(key) + 1, title:, note:, done:, later:, locked: project.step_locked?(key),
        current: key == current, openable: key != current && project.step_open?(key), waiting: }
    end
  end

  # A line about where your setup is at, while you're setting up.
  def project_setup_note(project)
    if !project.hackatime_linked? then "Nothing's linked yet, so your hours won't count."
    elsif project.hackatime_projects.none? && !project.waiting_for_hackatime_project? then "Hackatime's linked. Which project is yours?"
    elsif !project.setup_finished?
      project.tracking? ? "Hours count now. A couple of quick things and you're in." : "Hackatime's linked. #{project_links_itself(project)}"
    elsif project.waiting_for_hackatime_project? then "All set. #{project_links_itself(project)}"
    end
  end

  # =SETUP(hackatime, project) → #REF! until Hackatime's linked, #N/A while your hours don't count yet (no Hackatime
  # project linked), then TRUE.
  def project_formula(project)
    result = if !project.set_up? then "#REF!" elsif !project.tracking? then "#N/A" else "TRUE" end
    "=SETUP(hackatime, project)  →  #{result}"
  end

  # "Daily pace", or "Session pace" when you only build on weekends.
  def project_pace_name(project)
    project.build_time == "weekends" ? "Session pace" : "Daily pace"
  end

  # Hours logged, your daily pace (which you can change) and when you'd be done at it. (Ship day's the program's
  # deadline, on the Events card: this is the day your hours would be in.)
  def project_goal(project)
    [
      { label: "Logged", value: project_hours_label(project, project.hours_unspent_logged), note: "for the #{project.prize_name}" },
      { label: project_pace_name(project), value: project_pace_label(project.pace_minutes), note: BUILD_TIME_LABELS.fetch(project.build_time),
        pace: true },
      project_done_by(project)
    ]
  end

  # D-078: in the last third of the program (Program::GOAL_SALIENCE_STARTS_AT) the page leads with the minutes left to the goal
  # prize, while there are some.
  def project_goal_left?(project)
    Program.goal_salient? && project.tracking? && project.chosen_prize.present? && project.hours_to_go.positive?
  end

  # The same hours_to_go the Done by tile and the schedule use, in minutes.
  def project_minutes_left(project)
    (project.hours_to_go * 60).round
  end

  # The Done by tile: reached, or the day you'd finish at your pace, never one after the deadline.
  def project_done_by(project)
    if project.hours_to_go.zero? then { label: "Done by", value: "Reached", note: "you've logged enough" }
    elsif project.finish_on > project.deadline then { label: "Done by", value: "Too late", note: "at this pace" }
    else { label: "Done by", value: project_date(project.finish_on), note: "at this pace" }
    end
  end

  # The daily pace picker's options: each with whether it finishes your prize by the deadline, and why not if it doesn't.
  # When none can, they all stay open: the note says to pick a cheaper prize.
  # A "Just enough" option (Project#just_enough_pace) stands in for a preset of the same minutes, and your own pace,
  # if it's neither, keeps its place as a plain one.
  def project_pace_options(project)
    open = project.feasible_paces.none?
    just = project.just_enough_pace
    minutes = (Project::PACES - [ just ] + [ just, (project.pace_minutes unless Project::PACES.include?(project.pace_minutes)) ]).compact.uniq.sort
    minutes.map do |value|
      feasible = open || project.pace_feasible?(value)
      label = value == just ? "Just enough · #{project_pace_label(value)}" : project_pace_label(value)
      { minutes: value, label:, feasible:, just_enough: value == just, reason: (feasible ? nil : "Too slow for #{project_date(project.deadline)}") }
    end
  end

  # A line under the pace picker when it matters: a pace can't make it, or none can.
  def project_pace_note(project)
    if project.feasible_paces.none?
      "Even #{project_pace_label(Project::PACES.last)} a day can't get you the #{project.prize_name} by #{project_date(project.deadline)}. Pick a cheaper prize."
    elsif project.feasible_paces.size < Project::PACES.size
      "Slower paces can't get you the #{project.prize_name} by #{project_date(project.deadline)}."
    end
  end

  # "14 sessions of 45 min gets you there by Oct 16. Ship any time up to Oct 20."
  def project_schedule_note(project)
    to_go = project.upcoming_minutes.size
    "#{pluralize(to_go, "session")} of #{project_pace_label(project.pace_minutes)} gets you there by " \
      "#{project_date(project.finish_on)}. Ship any time up to #{project_date(project.deadline)}."
  end

  # What to do next with your prize, from where it stands: { state:, text:, action: { label:, icon:, path: } or nil }, or nil
  # while you're still building towards it (the schedule note says that). The shop's own state (ShopHelper#shop_state)
  # tells claimed from ready to claim.
  def project_next_step(project)
    prize = project.chosen_prize
    return unless prize && project.tracking?

    order = shop_order_for(project, prize)
    state = shop_state(project, prize, order)
    ship = { label: "Ship it", icon: "rocket-fill", path: project_ship_path } if project.may_ship? && !project.ship_waiting?
    if state == "claimed"
      { state: "claimed", text: order.ordered? ? "Your #{prize.name} is ordered and on its way." : "You've claimed the #{prize.name}. It's in the queue to be ordered." }
    elsif state == "ready"
      { state: "ready", text: "Approved. Your #{prize.name} is ready to claim.",
        action: { label: "Claim it", icon: "gift-fill", path: shop_path(anchor: "shop-#{prize.key}") } }
    elsif project.ship_in_review
      { state: "review", text: "Your ship's in review. You can claim the #{prize.name} once it's approved." }
    elsif project.ships.max_by(&:id)&.changes_needed?
      { state: "changes", text: "Your ship needs changes. Fix them and ship again.", action: ship&.merge(label: "Ship again") }
    elsif project.hours_to_go.zero?
      { state: "ship", text: "You've logged enough for the #{project.prize_name}. Next, ship your game.", action: ship }
    end
  end

  # D-112: what the reviewer wrote to the participant on their latest approved ship, or nil when they wrote nothing there. An earlier
  # approved ship's message doesn't stand in for a later one's.
  def project_reviewer_note(project)
    project.latest_approved_ship&.review_feedback.presence
  end

  # The milestones along your hours track: just your prize, at the hours it takes (D-018 took the 5-hour shoutout
  # off). Whether you've reached it. `logged` is what's counted towards it: your logged hours less what you've spent,
  # or any number (the /dev gallery).
  def project_milestones(project, logged: project.hours_unspent_logged)
    hours = project.hours_needed
    [ { hours:, label: "#{project_hours(hours)} hrs · #{project.prize_short}", reached: logged >= hours, at: 100.0, last: true,
        hours_text: project_hours(hours), name: project.prize_short } ]
  end

  def project_hours_percent(project, logged: project.hours_unspent_logged)
    [ logged * 100.0 / project_milestones(project).last[:hours], 100 ].min
  end

  # Your build days as cells. The days gone show how they went, from Hackatime: "hit" with your pace's minutes on
  # your linked projects (or more), "some" with less, or "missed" with none. Today shows its time so far (and fills in the same way, under its ring) once there is some. Ahead of it
  # are the play party, the day your hours would be in ("goal") and the deadline ("due"):
  # on its own after a gap when your days end before it, or in among them when they run on past it. Days run on
  # streak time (2am to 2am where you are), like the streak does.
  def project_schedule(project, today: project.user.streak_today_date)
    days = project.build_days(today:)
    deadline = project.deadline
    # Each day still to come takes your pace, but the last one only what's left of your goal, and today only what's left of
    # its pace (your hours logged already count what it has built).
    plan = project.upcoming_minutes(today:)
    sessions = plan.transform_values { |minutes| project_day_time(minutes.round * 60) }
    seconds = project.user.streak_activities.for_range(days.first..today).pluck(:activity_date, :coded_seconds).to_h
    cells = days.map.with_index do |day, index|
      label = index.zero? || day.day == 1 ? project_date(day) : day.day.to_s
      built = seconds.fetch(day, 0)
      how = if built.zero? then "missed" elsif built >= project.pace_minutes * 60 then "hit" else "some" end
      # Ahead of today a day shows the time it takes at your pace, with its marker (Goal, Party, Due) under it. Today
      # shows what you've built (its tooltip, of how much), or the time it takes while you've built nothing.
      state, value, note =
        if day == today then [ "today", built.zero? ? sessions[day] : project_day_time(built) ]
        elsif day < today then [ how, built.zero? ? "0" : project_day_time(built) ]
        elsif day == deadline then [ "due", "Due", (sessions[day] unless index == days.size - 1) ]
        elsif index == days.size - 1 then [ "goal", sessions[day], "Goal" ]
        elsif day == Program::PLAY_PARTY_ON then [ "party", sessions[day], "Party" ]
        else [ nil, sessions[day] ]
        end
      { date: label, state:, value:, note:, built: (how if day == today && !built.zero?),
        title: (day == today ? "#{project_day_time(built)} of #{project_day_time([ project.pace_minutes * 60, built + plan.fetch(day, 0) * 60 ].min)} today" : nil) }
    end
    cells = days.zip(cells).reject { |day, _| day > deadline }.map(&:last)
    if days.last < deadline
      cells << { gap: true } if days.last < deadline - 1
      cells << { date: deadline.day.to_s, state: "due", value: "Due" }
    end
    cells
  end

  # A day's building, short enough for its cell: "45m" under an hour, "1.5h" from there.
  def project_day_time(seconds)
    minutes = seconds / 60
    minutes < 60 ? "#{minutes}m" : "#{project_hours((seconds / 360.0).round / 10.0)}h"
  end

  # A calendar-page date for the Events card: "OCT" over "8".
  def project_event_date(date)
    safe_join([ tag.span(date.strftime("%b"), class: "project__event-month"), tag.span(date.day, class: "project__event-day") ])
  end

  # "Today: 45 min, this evening". What's left of your pace today, or of your goal if that's less. "Today: done" once
  # you've met your pace.
  def project_today(project)
    today = project.user.streak_today_date
    plan = project.hours_to_go.positive? ? project.upcoming_minutes(today:) : {}
    return "Today: done" if plan.any? && !plan.key?(today) && project.build_day?(today) && today >= project.build_start

    minutes = plan.key?(today) ? plan[today].round : project.hours_to_go.positive? ? [ project.pace_minutes, project_minutes_left(project) ].min : project.pace_minutes
    "Today: #{project_pace_label(minutes)}, #{BUILD_TIME_SOON.fetch(project.build_time)}"
  end

  # When your streak was last checked with Hackatime: "Checked just now", "Checked 5 minutes ago".
  def project_streak_checked(user)
    checked_at = user.streak_synced_at
    if checked_at.nil? then "Not checked yet"
    elsif checked_at > 1.minute.ago then "Checked just now"
    else "Checked #{time_ago_in_words(checked_at)} ago"
    end
  end

  # This week on your streak card, Sunday to Saturday, with the days you hit 20 minutes.
  def project_streak_week(project)
    project.user.streak_week
  end

  # Streak rewards (Reward::STREAK), earned or how many days off. The first one you haven't earned is next.
  def project_rewards(project)
    streak = project.streak
    rewards = Reward::STREAK.map { |reward| reward.merge(earned: project.user.earned?(reward[:key])) }
    upcoming = rewards.find { |reward| !reward[:earned] }
    rewards.map do |reward|
      state = if reward[:earned] then "earned" elsif reward.equal?(upcoming) then "next" else "later" end
      reward.merge(state:, status: reward[:earned] ? "Earned" : pluralize([ reward[:days] - streak, 1 ].max, "day"))
    end
  end

  # Everyone set up, ranked by hours this week or streak (Leaderboard), and you (last, with dashes, until you're set
  # up, or for good if you're an admin, who's never ranked: D-032). A pair that's done a pomodoro together shows your
  # buddy, and the week board shows how far you've moved since yesterday's snapshot.
  def leaderboard(you, sort: "total", date: Leaderboard.date_for(you.user))
    places = Leaderboard.places(sort:, date:)
    places << Leaderboard::Place.new(project: you, rank: places.size + 1, above: nil) unless places.any? { |place| place.project == you }
    places.map do |place|
      project = place.project
      mine = project == you
      { rank: place.rank, you: mine, name: mine ? "You" : project.user.public_name,
        user: project.user, building: project.title, off: !project.set_up? || project.user.listed_admin?,
        hidden: mine && project.user.listed_admin?,
        screenshot: (project.screenshot if project.screenshot.attached? && project.screenshot.blob.persisted?),
        hours: (sort == "today" ? project.hours_today(today: date) : project.hours_logged), streak: project.streak,
        change: (place.change if sort == "total" && project.set_up?),
        buddy: leaderboard_buddy(project) }
    end
  end

  # What the board shows you (D-078 item 8): the top three, then you with the five above and five below, and a [:gap, n]
  # marker wherever the list skips n people. Everyone when you ask for it, or when you're an admin (no row of your own).
  # Not set up yet: just the top three.
  LEADERBOARD_REACH = 5
  def leaderboard_window(rows, all: false)
    rows = rows.reject { |row| row[:hidden] }
    me = rows.index { |row| row[:you] }
    return rows if all || me.nil?

    keep = (0...[ 3, rows.size ].min).to_a
    keep |= ([ me - LEADERBOARD_REACH, 0 ].max..[ me + LEADERBOARD_REACH, rows.size - 1 ].min).to_a unless rows[me][:off]
    keep -= [ me ] if rows[me][:off]
    keep = keep.each_cons(2).flat_map { |a, b| b - a == 2 ? [ a, a + 1 ] : [ a ] }.push(keep.last).uniq if keep.size > 1 # a gap of one is just that person
    keep.each_with_index.flat_map do |index, at|
      skipped = at.zero? ? 0 : index - keep[at - 1] - 1
      skipped.positive? ? [ [ :gap, skipped ], rows[index] ] : [ rows[index] ]
    end
  end

  # The top three today as stairs (second, first, third), with you on a step of your own if you're further down,
  # and how far it is to pass whoever's just above you.
  def leaderboard_stairs(you)
    rows = leaderboard(you, sort: "today").reject { |row| row[:off] && (!row[:you] || row[:hidden]) }
    mine = rows.find { |row| row[:you] }
    return [ rows.first(3).values_at(1, 0, 2).compact.map { |row| row.merge(place: row[:rank].to_s, label: row[:rank].to_s, icon: true) },
             "Today. Admins aren't ranked." ] unless mine
    places = rows.first(3).values_at(1, 0, 2).compact.map { |row| row.merge(place: row[:rank].to_s, label: row[:rank].to_s, icon: true) }
    places << mine.merge(place: "you", label: "##{mine[:rank]}") if mine[:rank] > 3
    above = rows[rows.index(mine) - 1] if mine[:rank] > 1
    note = above ? "Today · #{(above[:hours] - mine[:hours]).round(1)} hrs to pass #{above[:name]}" : "Today. You're in first."
    [ places, note ]
  end

  # The sidebar's cards once you're set up, as the rows they fold into: your streak, your buddy, the play party and
  # where you are on the leaderboard. Your streak's open, unless your buddy needs you (a pomodoro to join).
  def project_side_sections(project)
    buddy = project.buddy
    live = project.pair&.live_pomodoro
    buddy_waiting = live.present? && !live.in?(project)
    mine = leaderboard(project, sort: "today").find { |row| row[:you] }
    sections = {
      streak: { icon: "local-fire-department", label: "Day streak",
                value: project.streak.positive? ? pluralize(project.streak, "day") : "Not yet", tone: project.streak.positive? ? "good" : "quiet" },
      buddy: { icon: "group", label: buddy ? "You + #{buddy_name(buddy)}" : "Buddy",
               value: buddy ? "#{pair_hours(project)[:together]} hrs" : project.buddy_invited? ? "Pending" : "Invite",
               tone: buddy ? nil : project.buddy_invited? ? "pending" : "link", dot: buddy_waiting },
      events: { icon: "event", label: "Play party", value: project_date(Program::PLAY_PARTY_ON), tone: "party" },
      leaderboard: { icon: "leaderboard", label: "Leaderboard", value: mine[:hidden] ? "—" : "##{mine[:rank]}" }
    }
    sections[buddy_waiting ? :buddy : :streak][:open] = true
    sections.to_h { |key, section| [ key, section.merge(key:) ] }
  end


  # "Start building and your project links itself once you log time."
  def project_links_itself(project)
    "Start building and your project links itself once you log time."
  end

  private
    # Your buddy, once the two of you have done a pomodoro together.
    def leaderboard_buddy(project)
      pair = project.pair
      pair.buddy_of(project) if pair&.pomodoro_together?
    end

    def project_step_label(project, key, done)
      case key
      when "hackatime" then done ? [ "Hackatime linked" ] : [ "Link Hackatime" ]
      when "hackatime_project"
        if project.hackatime_projects.any? && done then [ "Linked to #{project.hackatime_projects.to_sentence}" ]
        elsif project.hackatime_projects.any? then [ "Change your Hackatime projects" ]
        elsif project.step_locked?(key) then [ "Link your Hackatime project", "after Hackatime" ]
        elsif project.waiting_for_hackatime_project? then [ "Log your first time on Hackatime", "it links itself" ]
        else [ "Link your Hackatime project", "so your hours count" ]
        end
      when "repo"
        if project.repo_url.present? && project.errors[:repo_url].none? then [ "Repo added" ]
        elsif done then [ "Git repo", "add before you ship" ]
        else [ "Add your git repo", "before you ship" ]
        end
      when "buddy"
        if (buddy = project.buddy) then [ "Paired with #{buddy_name(buddy)}" ]
        elsif project.buddy_invited? then [ "Buddy invite sent", "you'll be paired when they sign up" ]
        elsif done then [ "Buddy skipped", "you can pair up any time" ]
        else [ "Bring a buddy", "optional" ]
        end
      end
    end
end
