# D-098: the bot's DM when a ship becomes approved (its fraud check passed, so its hours are spendable), framed as progress
# toward their goal prize. Ship queues it (NudgeApprovedJob). One DM for each ship, whatever re-saves the ship does. It keeps
# to what the other DMs keep to: nothing to admins or to someone who stopped the bot, and quiet hours or anything the bot said
# within Nudge::MESSAGE_GAP make it wait rather than drop. Unlike the others it still sends after Program::ENDS_AT, because
# reviews go on after the end. D-112: when the reviewer wrote a message to the participant with the verdict (review_feedback), the
# DM carries it after its usual line (Nudge::Copy.with_reviewer_note).
module Nudge::Approved
  KIND = "approved"
  # Goal not reached yet, goal reached, and no goal to speak of (none picked, or already claimed).
  SHORT = "approved_short"
  REACHED = "approved_reached"
  NO_GOAL = "approved_no_goal"

  def self.queue(ship)
    NudgeApprovedJob.perform_later(ship.id)
  end

  # Their DM for the ship. Returns the nudge once sent, a time when it has to wait until then, or nil when none is owed
  # (sent already, not approved, an admin, stopped, not on Slack). Under a lock on them, so two jobs can't both send it.
  def self.deliver(ship, now = Time.current)
    user = ship.project.user
    user.with_lock do
      return unless ship.reload.approved? && due?(ship, user, now)

      later = Nudge::Context.new(user, now).cheer_waits_until
      return later if later

      nudge = user.nudges.new(kind: KIND, arm: arm_for(ship.project), ship_id: ship.id, propensity: 1.0)
      nudge.deliver!(vars(ship), note: ship.review_feedback)
      nudge
    end
  end

  # No DM for this ship yet, and they're someone the bot may DM.
  def self.due?(ship, user, now)
    return false if user.listed_admin? || user.nudges.delivered.where(kind: KIND, ship_id: ship.id).exists?

    Nudge::Context.new(user, now).reachable?
  end

  def self.arm_for(project)
    if project.chosen_prize.nil? || project.goal_claimed? then NO_GOAL
    elsif project.goal_reached? then REACHED
    else SHORT
    end
  end

  # What the copy fills in. `added` is what this ship put on the approved hours (left out when it added none, so copy that
  # names it isn't picked). `approved` is what they can spend, so it adds up with `still` to the goal's hours.
  def self.vars(ship)
    project = ship.project.reload
    helpers = ApplicationController.helpers
    earlier = project.ships.select { |other| other.approved? && other.id != ship.id }.map { |other| other.approved_hours || other.hours }.max.to_f
    added = ((ship.approved_hours || ship.hours).to_f - earlier).round(2)
    goal = project.chosen_prize unless project.goal_claimed?
    approved = goal ? project.hours_to_spend : project.hours_approved
    vars = { approved: helpers.project_hours(approved), approved_word: unit(approved, "hour") }
    vars.merge!(added: helpers.project_hours(added), added_word: unit(added, "hour")) if added.positive?
    if goal
      still = [ (goal.hours - approved).round(1), 0 ].max
      vars.merge!(goal: goal.with_article, goal_hours: helpers.project_hours(goal.hours), still: helpers.project_hours(still), still_word: unit(still, "hour"))
    end
    vars
  end

  def self.unit(count, word) = count == 1 ? word : "#{word}s"
end
