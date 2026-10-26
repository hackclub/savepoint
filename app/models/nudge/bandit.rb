# Thompson sampling over how a nudge is framed, learned separately per bucket (like "behind"). Each arm is a
# Beta(successes, failures) guess at how often it gets someone building; we draw from each guess and send the
# highest draw, so arms we're unsure about still get tried. An arm this person was sent recently has its draw cut
# (recency_multipliers), so the same framing doesn't land day after day. Cheers (Nudge::Cheer) are their own bucket, learned on
# whether they build again the next day.
class Nudge::Bandit
  # Which arms make sense in each state. A streak message to someone with no streak is a wasted send.
  ARMS = {
    "zero_hours" => %w[pledge tiny_step social],
    "on_pace" => %w[streak progress pledge overtake],
    "behind" => %w[progress tiny_step pledge social overtake],
    "lapsed" => %w[tiny_step social pledge overtake],
    "cheer" => %w[cheer_done cheer_progress cheer_streak cheer_tomorrow cheer_social]
  }.freeze

  # What the holdout gets instead: our best guess, never learned. Comparing against them is how we know the bandit
  # helps at all.
  HOLDOUT_ARMS = { "zero_hours" => "pledge", "on_pace" => "pledge", "behind" => "progress", "lapsed" => "tiny_step",
                   "cheer" => "cheer_progress" }.freeze
  HOLDOUT_SHARE = 0.1

  # The first two days pick uniformly, so every arm has data before the bandit starts leaning.
  EXPLORE_UNTIL = Program::DATES.begin + 2
  # How much each bucket borrows from how the arm does everywhere else, so a new bucket doesn't start cold.
  POOLED_WEIGHT = 0.2
  # Thompson sampling has no closed-form propensity, so we estimate it by drawing this many times.
  DRAWS = 1_000

  # An arm they were sent recently counts for less (D-078, after Duolingo's recency penalty, which decays over weeks with a
  # half-life of about 15 days). Each send multiplies the arm's draw by 1 - RECENCY_PENALTY * 0.5^(days since / half-life),
  # added up over its recent sends and kept above zero. This program is 10 days with a nudge a day, so the half-life is 2 days
  # (an arm sent yesterday has 0.7 of its penalty left, one from 4 days ago a quarter, 8 days ago hardly any), and the
  # penalty is half: an arm sent just now draws at half strength, enough to lose to an arm the bandit rates a bit lower, but
  # not enough to hide a clear winner. Sends older than RECENCY_LOOKBACK (4 half-lives, 6% of the weight) are left out.
  RECENCY_HALF_LIFE = 2.days
  RECENCY_PENALTY = 0.5
  RECENCY_LOOKBACK = 8.days

  def self.nudge_for(context, kind: "bandit", bucket: context.bucket)
    bandit = new(bucket)
    arm, propensity, holdout = bandit.pick(context)
    return unless arm
    context.user.nudges.new(kind:, bucket:, arm:, propensity:, holdout:)
  end

  # Same people every time, from their id.
  def self.holdout?(user)
    Digest::SHA256.hexdigest("save-point-holdout-#{user.id}").to_i(16) % 100 < HOLDOUT_SHARE * 100
  end

  attr_reader :bucket

  def initialize(bucket)
    @bucket = bucket
  end

  def state = bucket

  # Returns [arm, propensity, holdout], or nil when no arm fits right now.
  def pick(context)
    return [ HOLDOUT_ARMS.fetch(state), 1.0, true ] if self.class.holdout?(context.user)

    arms = available_arms(context)
    return if arms.empty?
    return [ arms.sample, 1.0 / arms.size, false ] if context.today < EXPLORE_UNTIL

    posteriors = arms.index_with { |arm| posterior(arm) }
    recency = recency_multipliers(context.user, context.now)
    winner = draw(posteriors, recency)
    propensity = DRAWS.times.count { draw(posteriors, recency) == winner }.fdiv(DRAWS)
    [ winner, propensity, false ]
  end

  # { arm => multiplier below 1 } for the arms this person was sent in the last RECENCY_LOOKBACK. The propensity is
  # estimated with the same multipliers, so the log still says how likely the pick really was.
  def recency_multipliers(user, now)
    sends = user.nudges.delivered.bandit.where(sent_at: now - RECENCY_LOOKBACK..now).pluck(:arm, :sent_at)
    sends.each_with_object(Hash.new(0.0)) { |(arm, sent_at), weights| weights[arm] += 0.5**((now - sent_at) / RECENCY_HALF_LIFE.to_f) }
         .transform_values { |weight| [ 1 - RECENCY_PENALTY * weight, 0.0 ].max }
  end

  # Arms for this state that this person can actually get: streak copy needs a streak, social needs peers, overtake
  # needs someone within reach above you.
  def available_arms(context)
    vars = context.vars
    ARMS.fetch(state).select do |arm|
      case arm
      when "streak", "cheer_streak" then vars.key?(:streak)
      when "social", "cheer_social", "overtake" then Nudge::Copy.renderable?(arm, vars)
      else true
      end
    end
  end

  # One draw from each arm's { arm => [a, b] }, each times its recency multiplier, and the arm with the highest.
  def draw(posteriors, recency = {})
    posteriors.max_by { |arm, (a, b)| beta_sample(a, b) * recency.fetch(arm, 1.0) }.first
  end

  # Beta(1, 1) to start, plus this bucket's results, plus a little of every other bucket's. An opt-out counts as
  # several failures.
  def posterior(arm)
    own = results(Nudge.bandit.scored.where(holdout: false, bucket:, arm:))
    pooled = results(Nudge.bandit.scored.where(holdout: false, arm:).where.not(bucket:))
    [ 1 + own[:successes] + POOLED_WEIGHT * pooled[:successes], 1 + own[:failures] + POOLED_WEIGHT * pooled[:failures] ]
  end

  def results(nudges)
    counts = nudges.group(:reward).count
    {
      successes: counts.fetch(1, 0),
      failures: counts.fetch(0, 0) + counts.fetch(Nudge::OPT_OUT_PENALTY, 0) * Nudge::OPT_OUT_PENALTY.abs
    }
  end

  # For the admin dashboard: each arm's { mean:, low:, high:, best: }, its guessed success rate with a 95% interval,
  # and how often it'd win a draw right now.
  def summary(arms = ARMS.fetch(state))
    posteriors = arms.index_with { |arm| posterior(arm) }
    samples = DRAWS.times.map { posteriors.transform_values { |(a, b)| beta_sample(a, b) } }
    wins = samples.map { |draw| draw.max_by(&:last).first }.tally
    posteriors.to_h do |arm, (a, b)|
      sorted = samples.map { |draw| draw[arm] }.sort
      [ arm, { mean: a / (a + b), low: sorted[(DRAWS * 0.025).floor], high: sorted[(DRAWS * 0.975).floor - 1], best: wins.fetch(arm, 0).fdiv(DRAWS) } ]
    end
  end

  private
    # Beta(a, b) from two gammas.
    def beta_sample(a, b)
      x = gamma_sample(a)
      x / (x + gamma_sample(b))
    end

    # Marsaglia–Tsang. Our shapes are always ≥ 1.
    def gamma_sample(shape)
      d = shape - 1.0 / 3
      c = 1 / Math.sqrt(9 * d)
      loop do
        x = normal_sample
        v = (1 + c * x)**3
        next if v <= 0
        return d * v if Math.log(rand) < 0.5 * x**2 + d - d * v + d * Math.log(v)
      end
    end

    def normal_sample
      Math.sqrt(-2 * Math.log(1 - rand)) * Math.cos(2 * Math::PI * rand)
    end
end
