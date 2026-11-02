# D-137: the bot's DM when a ship is rejected for good (not changes needed). It says so, that the project can't be shipped again,
# and the reviewer's note to the participant when the review has one (review_feedback, D-112), never the judgement or the fraud
# notes. Ship queues it (NudgeRejectedJob), except for a ship a ban rejected: that account gets the ban DM only (Nudge::Banned).
# One DM for each ship, and the same rules as Nudge::Approved: nothing to admins, someone who stopped the bot or a banned account,
# and quiet hours or the gap after another DM make it wait rather than drop.
#
# Ships rejected before this shipped get nothing. To send one for a ship id, on purpose:
#   bin/rails "nudges:rejected[<ship id>]"
module Nudge::Rejected
  KIND = "rejected"

  def self.queue(ship)
    NudgeRejectedJob.perform_later(ship.id)
  end

  # Their DM for the ship. Returns the nudge once sent, a time when it has to wait until then, or nil when none is owed.
  # Under a lock on them, so two jobs can't both send it.
  def self.deliver(ship, now = Time.current, include_note: true)
    user = ship.project.user
    user.with_lock do
      return unless ship.reload.status == "rejected" && due?(ship, user, now)

      later = Nudge::Context.new(user, now).cheer_waits_until
      return later if later

      nudge = user.nudges.new(kind: KIND, arm: KIND, ship_id: ship.id, propensity: 1.0)
      nudge.deliver!({ title: "*#{SlackText.escape(ship.project.title)}*" }, note: (ship.review_feedback if include_note))
      nudge
    end
  end

  def self.due?(ship, user, now)
    return false if user.listed_admin? || user.nudges.delivered.where(kind: KIND, ship_id: ship.id).exists?

    Nudge::Context.new(user, now).reachable?
  end

  # Sends the DM for one ship now, whenever it was rejected (the backfill D-137 leaves for Armand to run). Returns what deliver does.
  def self.send_for(ship_id, include_note: true)
    deliver(Ship.find(ship_id), include_note:)
  end
end
