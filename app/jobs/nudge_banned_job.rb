# The bot's DM when an account is banned (Nudge::Banned), the one DM a banned account gets. Quiet hours and the gap after the
# bot's last message make it wait, as for the others.
class NudgeBannedJob < ApplicationJob
  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    later = Nudge::Banned.deliver(user)
    self.class.set(wait_until: later).perform_later(user_id) if later.respond_to?(:acts_like_time?) && later.acts_like_time?
  end
end
