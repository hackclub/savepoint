# D-137: the bot's DM when an account is banned. It is the one DM a banned account gets: every other stays blocked (D-113).
# User queues it once the ban has committed (NudgeBannedJob), and only this kind passes the ban check (Nudge#deliver!). One DM for
# each account. It keeps to the other DMs' manners: nothing to admins or someone who stopped the bot, and quiet hours or the gap
# after another DM make it wait. A ban rejects the account's waiting ships too, and those send no rejection DMs (Ship).
module Nudge::Banned
  KIND = "banned"

  def self.queue(user)
    NudgeBannedJob.perform_later(user.id)
  end

  # Their DM. Returns the nudge once sent, a time when it has to wait until then, or nil when none is owed.
  def self.deliver(user, now = Time.current)
    user.with_lock do
      return unless user.banned? && due?(user, now)

      later = Nudge::Context.new(user, now).cheer_waits_until
      return later if later

      nudge = user.nudges.new(kind: KIND, arm: KIND, propensity: 1.0)
      nudge.deliver!({})
      nudge
    end
  end

  def self.due?(user, now)
    return false if user.listed_admin? || user.nudges.delivered.where(kind: KIND).exists?

    Nudge::Context.new(user, now).reachable?(allow_banned: true)
  end
end
