# The admin home (/admin): the one page for every admin number (D-073). What's waiting on an admin, then who's building, where
# people drop, prizes, sign-ups and NPS, growth and the daily history. The cheap sections are in the page; the heavy ones
# (growth, sign-ups and NPS answers, history) are lazy Turbo Frames that load from the actions below when scrolled to.
class Admin::HomeController < Admin::BaseController
  def show
    @waiting = { "Orders" => Order.waiting.count, "Ships" => Ship.pending.count, "Extensions" => Extension.pending.count }
    @summary = AdminSummary.cached
    @nps = NpsStats.new.last_7_days
    @totals = { "Projects" => Project.count, "People" => User.count }
  end

  # Totals, DAU/WAU/MAU, who comes back, the growth simulator and streaks: the public stats (PublicStats) in the admin look.
  def growth
    @stats = PublicStats.cached
    # Where the projected DAU's new builders come from (Growth::Simulator): with everyone's friends, or steady.
    @signups = params[:signups].presence_in(Growth::Simulator::SIGNUPS) || "word_of_mouth"
    render_section
  end

  # Who stopped, by how far they got (StuckPeople, D-078).
  def stuck
    @groups = StuckPeople.new.groups
    render_section
  end

  # The latest written NPS answers, and where sign-ups come from (UTM tags).
  def signups
    @nps = NpsStats.new
    @utm = UtmStats.new
    render_section
  end

  # Every number, day by day (Metric).
  def history
    @days, @values = Metric.history
    render_section
  end

  private
    # A frame request gets just the frame; opening the URL itself gets the page around it.
    def render_section = render(layout: turbo_frame_request? ? false : "save_point")
end
