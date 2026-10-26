# Save Point in numbers (PublicStats), for anyone, signed in or not.
class StatsController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  def show
    @stats = PublicStats.cached
    # Where the projected DAU's new builders come from (Growth::Simulator): with everyone's friends, or steady.
    @signups = params[:signups].presence_in(Growth::Simulator::SIGNUPS) || "word_of_mouth"
  end
end
