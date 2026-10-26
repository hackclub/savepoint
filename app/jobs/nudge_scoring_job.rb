# Hourly: whether each nudge whose window has closed worked, which is what the bandit learns from (see Nudge#score!).
class NudgeScoringJob < ApplicationJob
  def perform
    Nudge.score_due
  end
end
