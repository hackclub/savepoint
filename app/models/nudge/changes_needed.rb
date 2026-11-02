# D-139: the bot's DM when a ship gets Changes needed. It says what to do and until when they can ship again (Project#changes_needed_until),
# in their time zone, then carries the reviewer's note (review_feedback, D-112). Ship queues it (NudgeChangesNeededJob). One DM for each
# ship, with the rules of Nudge::Rejected: nothing to admins, someone who stopped the bot or a banned account, and quiet hours or the gap
# after another DM make it wait rather than drop. It still sends after Program::ENDS_AT, because reviews go on after the end.
module Nudge::ChangesNeeded
  KIND = "changes_needed"

  def self.queue(ship)
    NudgeChangesNeededJob.perform_later(ship.id)
  end

  # Their DM for the ship. Returns the nudge once sent, a time when it has to wait until then, or nil when none is owed.
  # Under a lock on them, so two jobs can't both send it.
  def self.deliver(ship, now = Time.current, include_note: true)
    user = ship.project.user
    user.with_lock do
      return unless ship.reload.changes_needed? && due?(ship, user, now)

      later = Nudge::Context.new(user, now).cheer_waits_until
      return later if later

      nudge = user.nudges.new(kind: KIND, arm: KIND, ship_id: ship.id, propensity: 1.0)
      nudge.deliver!(vars(ship), note: (ship.review_feedback if include_note))
      nudge
    end
  end

  def self.due?(ship, user, now)
    return false if user.listed_admin? || user.nudges.delivered.where(kind: KIND, ship_id: ship.id).exists?

    Nudge::Context.new(user, now).reachable?
  end

  # The title, and the end of this ship's window in their time zone, like "Tue Nov 3, 11:42 pm". The window is the project's own
  # (Project#changes_needed_until), which a later verdict on another ship can end: then this ship's own 24 hours or the cutoff.
  def self.vars(ship)
    project = ship.project
    until_time = [ ship.reviewed_at + Project::CHANGES_NEEDED_WINDOW, project.ship_cutoff ].max
    { title: "*#{SlackText.escape(project.title)}*", deadline: until_time.in_time_zone(project.user.time_zone).strftime("%a %b %-d, %-l:%M %P") }
  end

  # Sends the DM for one ship now, whenever it got Changes needed (what the admin MCP's send_verdict_dm calls, for ships decided before this
  # shipped). Returns what deliver does.
  def self.send_for(ship_id, include_note: true)
    deliver(Ship.find(ship_id), include_note:)
  end
end
