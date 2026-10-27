# D-096: the bot asking someone to ship once they have Project::SHIP_PROMPT_HOURS unshipped hours. Every streak sync
# (StreakActivity.sync_for_user!) checks, so it goes soon after the hours cross. One DM for each crossing: none until
# they have shipped since the last one. It keeps to what the other DMs keep to: nothing to admins, a muted or unreachable
# person, quiet hours, anything the bot said within Nudge::MESSAGE_GAP, or after Program::ENDS_AT. A DM held back by
# any of these is tried again on the next sync. No penalty comes with it.
module Nudge::ShipPrompt
  ARM = "ship_prompt"

  # Called from the sync, which has just brought the hours up to date.
  def self.queue(user)
    project = Project.find_by(user_id: user.id)
    NudgeShipPromptJob.perform_later(user.id) if project && Time.current < Program::ENDS_AT && project.ship_prompt_due?
  end

  # Their DM, if one is due now. Under a lock on them, so two syncs at once can't both send it.
  def self.deliver(user, now = Time.current)
    user.with_lock do
      project = user.project
      return unless project&.tracking? && sendable?(user, project, now)

      context = Nudge::Context.new(user, now)
      return unless context.reachable? && !context.quiet? && !context.just_messaged?

      nudge = user.nudges.new(kind: "ship_prompt", arm: ARM, propensity: 1.0)
      nudge.deliver!(vars(context))
      nudge
    end
  end

  # Past the threshold, still able to ship, not an admin, the program running, and not told already for this crossing.
  def self.sendable?(user, project, now)
    return false if now >= Program::ENDS_AT || user.listed_admin? || !project.may_ship?(now:)

    project.ship_prompt_due? && !told_since_last_ship?(user, project)
  end

  # A DM went out after their latest standing ship (or ever, if they have shipped nothing), so this crossing has had one.
  def self.told_since_last_ship?(user, project)
    last_ship = project.ships.select { it.pending? || it.approved? }.max_by(&:id)
    sent = user.nudges.delivered.where(arm: ARM)
    sent = sent.where(sent_at: last_ship.created_at..) if last_ship
    sent.exists?
  end

  def self.vars(context)
    project = context.project
    { title: SlackText.escape(project.title.downcase_first), unshipped: ApplicationController.helpers.project_hours(project.unshipped_hours) }
  end
end
