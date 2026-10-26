# The stats page everyone sees (StatsController), with the admin nav over it instead of the participant top bar.
class Admin::StatsController < Admin::BaseController
  def show
    @stats = PublicStats.cached
    # Where the projected DAU's new builders come from (Growth::Simulator): with everyone's friends, or steady.
    @signups = params[:signups].presence_in(Growth::Simulator::SIGNUPS) || "word_of_mouth"
  end
end
