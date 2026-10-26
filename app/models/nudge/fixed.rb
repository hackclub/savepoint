# Nudges that always send when they apply, so the bandit never learns from them. The first one that applies wins:
# a program date, then a milestone, then a missing setup step, then saving a streak, then coming back after a missed day.
module Nudge::Fixed
  # Save Point's own dates, for them: kickoff is everyone's, the last days go by their deadline (Project#deadline).
  def self.program_dates(context)
    deadline = context.project.deadline
    { "kickoff" => Program::DATES.begin, "three_days_left" => deadline - 3, "last_day" => deadline }
  end

  # Hours on Hackatime that each milestone is for, in order: your first, halfway to your pick's price, and there
  # (Project#hours_needed). Each sends once, and reaching a later one first means the earlier ones don't send at all.
  def self.milestones(context)
    needed = context.project.hours_needed
    { "first_session" => 0.1, "halfway" => needed / 2.0, "done" => needed }
  end

  # Sent at their slot, so streak savers come with the day's nudge rather than at 11pm.
  def self.for(context)
    program_nudge(context) || milestone(context) || setup_nudge(context) || streak_saver(context) || comeback(context)
  end

  # Each once: ones sent for an earlier deadline (before this one's last three days) don't count, so a moved
  # deadline (Save Point running a week longer) brings the last days round again.
  def self.program_nudge(context)
    dates = program_dates(context)
    key = dates.key(context.today) or return
    key = "#{key}_done" if key != "kickoff" && context.project.afford?
    since = dates["three_days_left"].in_time_zone(context.user.time_zone)
    return if context.user.nudges.delivered.where(kind: "program", arm: key, sent_at: since..).exists?
    build(context, kind: "program", arm: key)
  end

  def self.milestone(context)
    milestones = milestones(context)
    key = milestones.select { |_, hours| context.hours >= hours }.keys.last or return
    later = milestones.keys.drop(milestones.keys.index(key))
    return if context.user.nudges.delivered.where(kind: "milestone", arm: later).exists?
    build(context, kind: "milestone", arm: key)
  end

  # One step at a time, in the order the project page lists them, and not every day. After linking Hackatime comes
  # getting time onto it: with nothing there since Save Point started, the bot says how (the editor plugin);
  # with time there and no project picked, it asks you to pick one. (A new project with time on it was
  # linked for you before any of this, by Nudge::Context#refresh!, and that DM is the day's message.)
  def self.setup_nudge(context)
    project = context.project
    step =
      if !project.hackatime_linked? then "hackatime"
      elsif (hackatime_step = hackatime_project_step(context)) then hackatime_step
      elsif project.repo_url.blank? && !project.repo_later? then "repo"
      end
    return unless step
    return if context.user.nudges.delivered.where(kind: "setup", arm: step, sent_at: context.now - Nudge::Context::SETUP_EVERY..).exists?
    build(context, kind: "setup", arm: step)
  end

  # Picking your Hackatime project, or getting time onto Hackatime first (the plugin): whichever's
  # next, or nothing once a project's picked or while Hackatime can't be reached.
  def self.hackatime_project_step(context)
    project = context.project
    return if project.hackatime_projects.any?

    available = context.available_hackatime_projects or return
    return "hackatime_project" if available.any? { |each| each.seconds.positive? }
    "plugin"
  end

  def self.streak_saver(context)
    return unless context.streak >= 2 && context.minutes_today < Nudge::REWARD_MINUTES
    return if context.user.nudges.delivered.where(kind: "streak_saver", sent_at: context.now - context.streak.days..).exists?
    build(context, kind: "streak_saver", arm: "streak_saver")
  end

  # After a missed day, to someone who has built before (D-078): one DM per missed day, in the place of a bandit send since
  # the scheduler gives each person one DM a day at most. It promises a free sticker pack for coding Reward::STICKERS_SECONDS
  # within Reward::COMEBACK_WINDOW, unless they can't have one (Context#stickers_to_promise?). built_on is the day missed.
  # Streak saver never overlaps it: that is for someone who built yesterday, and this for someone who did not.
  def self.comeback(context)
    missed = context.comeback_missed_on or return
    return if context.user.nudges.delivered.where(kind: "comeback", built_on: missed).exists?

    promise = context.stickers_to_promise?
    build(context, kind: "comeback", arm: promise ? "comeback_stickers" : "comeback").tap do |nudge|
      nudge.assign_attributes(built_on: missed, stickers_promised: promise)
    end
  end

  def self.build(context, kind:, arm:)
    context.user.nudges.new(kind:, arm:, propensity: 1.0)
  end
end
