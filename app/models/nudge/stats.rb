# What the admin dashboard shows about the bot's nudges: how many went out and what came of them, the bandit against
# the holdout, each bucket's arms as the bandit sees them, and the fixed nudges.
class Nudge::Stats
  # Counts for some nudges. Worked and didn't work are of the scored ones; an opt-out is one that didn't work (and counts for
  # more, to the bandit). Not delivery failures: those are failed_dms below.
  Row = Data.define(:sent, :clicked, :scored, :worked, :opted_out) do
    def self.empty = new(sent: 0, clicked: 0, scored: 0, worked: 0, opted_out: 0)

    def click_rate = sent.zero? ? nil : clicked.fdiv(sent)
    def work_rate = scored.zero? ? nil : worked.fdiv(scored)
    def didnt_work = scored - worked
  end

  COUNTS = [ "COUNT(*)", "COUNT(clicked_at)", "COUNT(reward)", "COUNT(*) FILTER (WHERE reward = 1)",
             "COUNT(opted_out_at)" ].map { |sql| Arel.sql(sql) }.freeze

  attr_reader :nudges

  def initialize(nudges = Nudge.delivered.real)
    @nudges = nudges
  end

  def totals = row(nudges)

  def muted_users = User.where.not(slack_muted_at: nil).count
  def failed_dms = User.where.not(slack_dm_failed_at: nil).count

  # Who the bot couldn't DM, and why (Slack's error code, nil for failures before it was kept).
  def failed_dm_details
    User.where.not(slack_dm_failed_at: nil).order(:slack_dm_failed_at).pluck(:id, :slack_dm_error, :slack_dm_failed_at)
        .map { |id, error, failed_at| { user_id: id, error:, failed_at: } }
  end

  def waiting = nudges.unscored.count

  # The bandit's picks against the holdout's fixed best guesses: whether learning helps at all.
  def policies
    { "Bandit" => row(nudges.bandit.where(holdout: false)), "Holdout" => row(nudges.bandit.where(holdout: true)) }
  end

  # Each bucket's arms: counts (holdout left out, like the bandit does) and the bandit's current guess.
  def buckets
    counts = grouped(nudges.bandit.where(holdout: false), :bucket, :arm)
    Nudge::Bandit::ARMS.to_h do |bucket, arms|
      summary = Nudge::Bandit.new(bucket).summary(arms)
      [ bucket, arms.map { |arm| { arm:, row: counts.fetch([ bucket, arm ], Row.empty), **summary.fetch(arm) } } ]
    end
  end

  def fixed
    grouped(nudges.where.not(kind: Nudge::LEARNED), :kind, :arm).sort_by { |_, row| -row.sent }
  end

  # Sends per day, bandit and not, for the last two weeks or so.
  def daily
    nudges.where(sent_at: 15.days.ago..).group(Arel.sql("DATE(sent_at)"), :kind).count
          .each_with_object(Hash.new { |hash, day| hash[day] = Hash.new(0) }) { |((day, kind), count), days| days[day][Nudge::LEARNED.include?(kind) ? "bandit" : "fixed"] += count }
          .sort.to_h
  end

  def recent(limit = 50)
    nudges.includes(:user).order(sent_at: :desc).limit(limit)
  end

  private
    def row(scope)
      sent, clicked, scored, worked, opted_out = scope.pick(*COUNTS)
      Row.new(sent:, clicked:, scored:, worked:, opted_out:)
    end

    def grouped(scope, *columns)
      scope.group(*columns).pluck(*columns, *COUNTS).to_h do |values|
        keys, (sent, clicked, scored, worked, opted_out) = values.first(columns.size), values.drop(columns.size)
        [ keys, Row.new(sent:, clicked:, scored:, worked:, opted_out:) ]
      end
    end
end
