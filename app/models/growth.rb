# Who's building, day by day, after Duolingo's growth model (as Stardance runs it): every builder, every day of
# Save Point, in one state by what they did on and before that day, and how many moved from each state one day to each
# state the next. Built on a day means ACTIVE_SECONDS or more on Hackatime that day (their synced streak day,
# StreakActivity): one minute, well short of a streak's twenty, since this asks who showed up, not who did their bit (D-075).
#
# Save Point runs about 10 days, so Duolingo's month-scale states (reactivated after 7 to 29 days away, resurrected after
# 30, at-risk MAU, dormant) never happen here and are gone. The states are the ones a 10-day program can have: three
# that built that day (new, built the day before too, back after days off) and two that didn't (skipped just today,
# gone two days or more). The three that built are the groups the admin and stats charts stack, and always sum to DAU.
#
# Only finished days are modelled (today's still filling in), and the whole thing is small enough to work out from
# the streak days each time, so nothing's snapshotted. PublicStats caches it with the rest of the page.
class Growth
  ACTIVE_SECONDS = 60
  # new: first day building. current: built the day before too. returning: built before, but not the day before.
  # at_risk: didn't build today, did yesterday. lapsed: didn't build today or yesterday, but did before.
  STATES = %w[new current returning at_risk lapsed].freeze
  ACTIVE_STATES = STATES.first(3).freeze
  # Rate => [state yesterday, state today]. NURR, CURR and RURR are Duolingo's names; the two ways back after days
  # off are named for what they are.
  RATES = {
    "nurr" => %w[new current],
    "curr" => %w[current current],
    "rurr" => %w[returning current],
    "day_off" => %w[at_risk returning],
    "days_off" => %w[lapsed returning]
  }.freeze
  # Daily rates are noisy with a program this size, so the rates shown pool several days.
  RATE_WINDOW = 7

  # One day: how many builders sat in each state, and how many moved from each state the day before into each
  # state today (`transitions[from][to]`).
  Day = Data.define(:date, :counts, :transitions) do
    def count_for(state) = counts.fetch(state, 0)
    def dau = ACTIVE_STATES.sum { |state| count_for(state) }

    # Builders who were in `from` yesterday, or nil if there were none.
    def users_leaving(from) = transitions.fetch(from, {}).values.sum.nonzero?

    def rate(name)
      from, to = RATES.fetch(name)
      total = users_leaving(from)
      total && transitions[from].fetch(to, 0).fdiv(total)
    end
  end

  # The model up to the end of the day before `today`, over the days of Save Point. `participants_only` leaves out
  # the admins on the list (D-032), as the admin pages do; the public stats page counts everyone.
  def initialize(today: Date.current, participants_only: false)
    @today = today
    @participants_only = participants_only
  end

  # A Day for every finished day of Save Point so far, oldest first.
  def days
    @days ||= begin
      previous = {}
      (Program::HACKATIME_START..[ @today - 1, Program::DATES.end ].min).map do |date|
        counts = Hash.new(0)
        transitions = Hash.new { |hash, from| hash[from] = Hash.new(0) }
        active_dates_by_user.each do |user_id, active_dates|
          state = self.class.state_on(active_dates, date) or next
          counts[state] += 1
          transitions[previous[user_id]][state] += 1 if previous[user_id]
          previous[user_id] = state
        end
        Day.new(date:, counts: counts.to_h, transitions: transitions.transform_values(&:to_h))
      end
    end
  end

  def latest = days.last

  # Each rate pooled over the RATE_WINDOW days ending that day: who left a state over the window, and where to.
  def pooled_rates
    days.each_index.map do |index|
      window = days[[ index - RATE_WINDOW + 1, 0 ].max..index]
      RATES.keys.to_h { |rate| [ rate.to_sym, pooled_rate(window, rate) ] }.merge(date: days[index].date)
    end
  end

  # Everything the stats page draws, as plain values (it's cached). Days still to come are there too, with nothing
  # in them, so the charts line up with the hours chart; today is in `today`, as far as it's got.
  def to_h
    rates = pooled_rates
    {
      active_minutes: ACTIVE_SECONDS / 60,
      days: Program::DATES.map { |date| row(date, days.find { |day| day.date == date }) },
      today: (row(@today, today_so_far) if Program::DATES.cover?(@today)),
      rates: Program::DATES.map { |date| rates.find { |row| row[:date] == date } || { date: } },
      latest: latest && { date: latest.date, dau: latest.dau, curr: rates.last[:curr] },
      projections: Simulator::SIGNUPS.to_h { |signups| [ signups, projection(signups) ] }
    }
  end

  # A builder's state on `day`, given the days they've built (sorted), or nil before their first.
  def self.state_on(active_dates, day)
    first = active_dates.first
    return if first.nil? || first > day

    built_yesterday = active_dates.include?(day - 1)
    if active_dates.include?(day)
      first == day ? "new" : built_yesterday ? "current" : "returning"
    else
      built_yesterday ? "at_risk" : "lapsed"
    end
  end

  private
    # The days each builder built ACTIVE_SECONDS or more, sorted.
    def active_dates_by_user
      activities = StreakActivity.where(activity_date: Program::HACKATIME_START.., coded_seconds: ACTIVE_SECONDS..)
      activities = activities.where(user_id: User.participants.select(:id)) if @participants_only
      @active_dates_by_user ||= activities.order(:activity_date).pluck(:user_id, :activity_date)
                                              .group_by(&:first).transform_values { |rows| rows.map(&:last) }
    end

    # Today as it stands, counted the same way (its transitions aren't kept: they'd move as the day fills in).
    def today_so_far
      return unless Program::DATES.cover?(@today)

      counts = Hash.new(0)
      active_dates_by_user.each_value do |active_dates|
        state = self.class.state_on(active_dates, @today) and counts[state] += 1
      end
      Day.new(date: @today, counts: counts.to_h, transitions: {})
    end

    # A day's numbers, or nil for each until the day's done.
    def row(date, day)
      { date:, future: day.nil?, dau: day&.dau, **STATES.to_h { |state| [ state.to_sym, day&.count_for(state) ] } }
    end

    def pooled_rate(window, rate)
      from, to = RATES.fetch(rate)
      leaving = window.sum { |day| day.users_leaving(from).to_i }
      return if leaving.zero?

      window.sum { |day| day.transitions.fetch(from, {}).fetch(to, 0) }.fdiv(leaving)
    end

    # DAU projected from the latest day to the end of Save Point, with nothing changed and with each rate improved.
    # Not until the rates have seen someone who'd built two days running face a third: before that, the model's
    # only guess for them is that they all leave.
    def projection(signups)
      return if latest.nil? || latest.date >= Program::DATES.end
      return unless days.last(Simulator::WINDOW).any? { |day| day.users_leaving("current") }

      simulator = Simulator.new(days, signups:, horizon: (Program::DATES.end - latest.date).to_i)
      levers = simulator.levers
      shown = levers.first(Simulator::PROJECTED_LEVERS)
      history = days.map { |day| { date: day.date, actual: day.dau } }
      history.last.merge!(baseline: latest.dau, **shown.to_h { |lever| [ lever.rate.to_sym, latest.dau ] })
      future = simulator.baseline.each_index.map do |index|
        { date: latest.date + index + 1, baseline: simulator.baseline[index].round,
          **shown.to_h { |lever| [ lever.rate.to_sym, lever.daily_dau[index].round ] } }
      end
      {
        horizon_days: simulator.horizon, new_per_day: simulator.new_per_day, signups_per_dau: simulator.signups_per_dau,
        baseline_dau: simulator.baseline_dau, rows: history + future,
        levers: levers.map { |lever| lever.to_h.except(:daily_dau) }
      }
    end
end
