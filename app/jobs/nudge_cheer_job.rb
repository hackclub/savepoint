# The bot's cheer for a streak day someone's just built their 20 minutes on (Nudge::Cheer). In quiet hours it waits
# for the morning, so a late night's building gets a "yesterday" cheer at 8am rather than nothing; and right after
# anything else the bot said, it waits the hour (Nudge::MESSAGE_GAP), so no two of its messages land together.
class NudgeCheerJob < ApplicationJob
  def perform(user_id, built_on)
    user = User.find_by(id: user_id)
    return unless user

    context = Nudge::Context.new(user, built_on:)
    return unless context.cheer_due?

    if (later = context.cheer_waits_until)
      self.class.set(wait_until: later).perform_later(user_id, built_on)
    else
      Nudge::Cheer.deliver(context)
    end
  end
end
