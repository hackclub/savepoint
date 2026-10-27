# Duolingo's lever analysis, as Stardance runs it, for the rest of Save Point: project DAU forward from the latest
# day's states using the recent transition rates, then again with one retention rate improved, and rank the rates
# by how much DAU they add by the last day.
#
# New builders either hold at their recent daily average (flat) or scale with yesterday's DAU (word of mouth).
# With word of mouth, every builder a better rate keeps also brings friends, so gains compound.
# Word of mouth is only as good as its rate, and the first days of a program are mostly people who came from the
# launch, not from friends: three newcomers after a day with no builders isn't a rate. So the rate is a ratio of
# sums over days that had MIN_DAU builders the day before, it needs MIN_WORD_OF_MOUTH_DAYS such days before it is
# offered, and the projection never asks for more new builders in a day than NEW_CEILING times the best day yet. Starting an
# improvement a couple of days later costs builder-days over the rest of Save Point that never come back (the
# last day's DAU alone barely notices: with our rates, who built early on hardly tells on it).
class Growth::Simulator
  # The days the rates are pooled over.
  WINDOW = 7
  # Each lever raises its rate by this much, relative (60% becomes 66%), from the first projected day.
  LIFT = 0.1
  DELAY_DAYS = 2
  SIGNUPS = %w[word_of_mouth flat].freeze
  LEVERS = %w[nurr curr rurr day_off days_off].freeze
  PROJECTED_LEVERS = 3
  # A day only counts towards the word-of-mouth rate if at least this many were building the day before. Under 10,
  # one builder is over 10% of the denominator, and the newcomers are mostly the launch's, not friends of builders.
  MIN_DAU = 10
  # Qualifying days needed before word of mouth is offered: three days of steady building, not one lucky ratio.
  MIN_WORD_OF_MOUTH_DAYS = 3
  # A lever's rate is only shown with this many builders having left its state over the window; fewer is anecdote.
  MIN_LEAVERS = 10
  # Word of mouth never projects more new builders in a day than this many times the most seen in one day so far.
  # It turns exponential growth into growth that stays within reach of what Save Point has already done.
  NEW_CEILING = 2
  # Where a state's builders go when the window saw nobody leave it.
  DECAY = {
    "new" => "at_risk",
    "current" => "at_risk",
    "returning" => "at_risk",
    "at_risk" => "lapsed",
    "lapsed" => "lapsed"
  }.freeze

  # `daily_dau` is the projected DAU for each day, starting the day after the latest; `lift` is what the lever
  # adds to the last day's, and `cost_of_waiting` the builder-days lost by starting it DELAY_DAYS later.
  Lever = Data.define(:rate, :current_rate, :daily_dau, :lift, :cost_of_waiting) do
    def dau = daily_dau.last
    def to_h = super.merge(dau:)
  end

  attr_reader :horizon, :new_per_day, :signups_per_dau

  # `days` are Growth::Days, oldest first; `horizon` is how many days to project.
  def initialize(days, signups: "word_of_mouth", horizon:)
    recent = days.last(WINDOW)
    @signups = signups
    @horizon = horizon
    @start = Growth::STATES.to_h { |state| [ state, recent.last.count_for(state).to_f ] }
    @new_per_day = recent.sum { |day| day.count_for("new") }.fdiv(recent.size)
    @word_of_mouth_pairs = days.last(WINDOW + 1).each_cons(2).select { |before, _| before.dau >= MIN_DAU }
    @signups_per_dau = word_of_mouth_rate
    @new_ceiling = NEW_CEILING * days.map { |day| day.count_for("new") }.max.to_f
    @leavers = Growth::STATES.index_with { |from| recent.sum { |day| day.users_leaving(from).to_i } }
    @matrix = pooled_matrix(recent)
  end

  # Whether there are enough days with a real denominator to trust the word-of-mouth rate.
  def word_of_mouth? = @word_of_mouth_pairs.size >= MIN_WORD_OF_MOUTH_DAYS

  def baseline = @baseline ||= project

  def baseline_dau = baseline.last

  def levers
    @levers ||= LEVERS.filter_map do |rate|
      from, to = Growth::RATES.fetch(rate)
      current_rate = @matrix[from].fetch(to, 0.0)
      next if current_rate.zero? || @leavers.fetch(from) < MIN_LEAVERS

      daily_dau = project(lever: [ from, to ])
      delayed = project(lever: [ from, to ], delay: DELAY_DAYS)
      Lever.new(rate:, current_rate:, daily_dau:, lift: daily_dau.last - baseline_dau,
                cost_of_waiting: [ daily_dau.zip(delayed).sum { |now, later| now - later }, 0 ].max)
    end.sort_by { |lever| -lever.lift }
  end

  private
    # New builders per active builder the day before: total newcomers over total prior DAU on the qualifying days
    # (a ratio of sums, so a day with few builders can't swing it).
    def word_of_mouth_rate
      prior_dau = @word_of_mouth_pairs.sum { |before, _| before.dau }
      prior_dau.zero? ? 0.0 : @word_of_mouth_pairs.sum { |_, after| after.count_for("new") }.fdiv(prior_dau)
    end

    def pooled_matrix(days)
      Growth::STATES.index_with do |from|
        targets = Hash.new(0)
        days.each { |day| day.transitions.fetch(from, {}).each { |to, users| targets[to] += users } }
        total = targets.values.sum
        total.zero? ? { DECAY.fetch(from) => 1.0 } : targets.transform_values { |users| users.fdiv(total) }
      end
    end

    # DAU for each day of the horizon. A lever starts improving `delay` days in.
    def project(lever: nil, delay: 0)
      counts = @start
      Array.new(horizon) do |index|
        matrix = lever && index >= delay ? lifted(lever) : @matrix
        counts = step(counts, matrix)
        Growth::ACTIVE_STATES.sum { |state| counts[state] }
      end
    end

    def step(counts, matrix)
      following = Hash.new(0.0)
      counts.each do |from, users|
        matrix.fetch(from).each { |to, share| following[to] += users * share }
      end
      following["new"] = signups(counts)
      following
    end

    def signups(counts)
      return @new_per_day if @signups == "flat"

      [ @signups_per_dau * Growth::ACTIVE_STATES.sum { |state| counts[state] }, @new_ceiling ].min
    end

    # Raises one transition by LIFT, capped at 1, and scales the rest of its row down so the row still sums to 1.
    def lifted((from, to))
      @lifted ||= {}
      @lifted[[ from, to ]] ||= begin
        row = @matrix.fetch(from)
        rate = row.fetch(to, 0.0)
        raised = [ rate * (1 + LIFT), 1.0 ].min
        rest = rate < 1 ? (1 - raised) / (1 - rate) : 0.0
        @matrix.merge(from => row.to_h { |target, share| [ target, target == to ? raised : share * rest ] })
      end
    end
end
