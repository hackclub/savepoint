# The bandit dashboard: how the bot's nudges are doing and what the bandit's learned (Nudge::Stats).
class Admin::NudgesController < Admin::BaseController
  def index
    @stats = Nudge::Stats.new
  end
end
