# The bot's DM asking someone to ship (Nudge::ShipPrompt), queued by a streak sync that finds them past the threshold.
class NudgeShipPromptJob < ApplicationJob
  def perform(user_id)
    user = User.find_by(id: user_id)
    Nudge::ShipPrompt.deliver(user) if user
  end
end
