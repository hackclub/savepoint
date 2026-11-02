# The bot's DM when a ship gets Changes needed (Nudge::ChangesNeeded). In quiet hours it waits for the morning, and right after anything
# else the bot said it waits out the gap (Nudge::MESSAGE_GAP), so the DM is late rather than lost.
class NudgeChangesNeededJob < ApplicationJob
  def perform(ship_id)
    ship = Ship.find_by(id: ship_id)
    return unless ship

    later = Nudge::ChangesNeeded.deliver(ship)
    self.class.set(wait_until: later).perform_later(ship_id) if later.respond_to?(:acts_like_time?) && later.acts_like_time?
  end
end
