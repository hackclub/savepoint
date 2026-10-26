module OnboardingHelper
  # The four questions, one panel each.
  def onboarding_steps
    [
      { label: "Game", question: "Which game are you building?" },
      { label: "Hackatime", question: "Which Hackatime project is it?" },
      { label: "Prize", question: "Pick your prize." },
      { label: "When", question: "When will you build?" }
    ]
  end

  # D-078 item 4: the progress strip counts signing in as done, then the four questions. 5 is the last step's number
  # in onboarding_step_reached (Start building).
  def onboarding_progress_labels
    [ "Signed in" ] + onboarding_steps.map { |step| step[:label] }
  end

  # How far along the strip starts: the furthest step reached, at least the first screen. Signing in is done, so it is never 0.
  def onboarding_done_count(user)
    (user&.onboarding_step_reached || 1).clamp(1, onboarding_progress_labels.size)
  end

  # The free stickers (D-051) as the sheet's reward, only while they can still be earned: an account made since they began,
  # YSWS-eligible and not banned, inside its first hour, without them already.
  def onboarding_sticker_promise?(user, now: Time.current)
    return false unless user&.created_at && user.created_at >= Reward::STICKERS_SINCE && user.sticker_eligible?

    now < user.created_at + Reward::STICKERS_WINDOW && !user.earned?("stickers")
  end

  # The tiles for the last step (D-037): each Project::BUILD_TIMES value with an icon and when its nudge arrives
  # (Nudge::SLOTS, so the hint and the nudge never disagree).
  def onboarding_build_times
    icons = { "after school" => "time-fill", "evening" => "sparkles-fill", "late night" => "star-fill", "weekends" => "calendar-fill" }
    Project::BUILD_TIMES.map do |time|
      hint = time == "weekends" ? "sat and sun, around #{onboarding_slot_time(time)}" : "around #{onboarding_slot_time(time)}"
      { value: time, icon: icons.fetch(time), hint: }
    end
  end

  # Every prize, fewest hours first (D-004), for the prize step.
  def onboarding_prizes
    Prize::ALL.sort_by(&:hours)
  end

  # "15:30" as "3:30", "19:00" as "7".
  def onboarding_slot_time(time)
    hour, minute = Nudge::SLOTS.fetch(time).split(":").map(&:to_i)
    hour = (hour - 1) % 12 + 1
    minute.zero? ? hour.to_s : format("%d:%02d", hour, minute)
  end

  # What step 2 shows: Hackatime projects you can pick from, or why not (you're signed out, haven't linked Hackatime,
  # or it can't be reached right now).
  # repo: the code link typed in step 1, if any. A project Hackatime links to a different repo goes last, with a warning
  # (D-064, the same as the project page). Hackatime is only asked for repo links when a repo was typed.
  def onboarding_hackatime(user, repo: nil)
    return { state: :signed_out } unless user
    return { state: :unlinked } unless user.hackatime_linked?

    { state: :ready, projects: Hackatime.pickable_projects(user), repo: Ship.with_scheme(repo) }
  rescue Hackatime::NotLinked
    { state: :unlinked }
  rescue Hackatime::Expired
    { state: :expired }
  rescue Hackatime::Unavailable
    { state: :ready, projects: [], problem: "Couldn't reach Hackatime just now. Skip for now, or try again in a minute." }
  end

  # The rows for step 2's picker, a project Hackatime links to another repo than `hackatime[:repo]` last.
  def onboarding_hackatime_choices(user, hackatime)
    repos = Project.hackatime_repo_links(user, hackatime[:repo])
    choices = hackatime[:projects].map do |choice|
      { name: choice.name, note: "#{project_hours(choice.hours)} hrs", linked: false,
        other_repo: Project.other_repo?(hackatime[:repo], choice.name, repos) }
    end
    choices.partition { |choice| !choice[:other_repo] }.flatten
  end
end
