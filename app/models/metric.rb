# Save Point's numbers, day by day: what the public stats page and the admin pages show now, kept (MetricSnapshot)
# so how they moved is on record, change by change. Days are UTC. Most are rebuilt from timestamps for any day
# (bin/rails metrics:backfill); the ones nothing dates (whether Hackatime's linked, streaks, who's muted the bot)
# are only ever taken for today, so they start the day the snapshots do.
class Metric
  Definition = Data.define(:key, :label, :cumulative, :dated, :value)

  # Each with how it's read: cumulative ones are totals as of the end of that day, the rest are that day's alone.
  DEFINITIONS = [
    # The funnel.
    [ "signed_in", "Signed in", true, true, ->(through) { participants.where(created_at: ..through).count } ],
    [ "pledged", "Pledged a project", true, true, ->(through) { projects.where(created_at: ..through).count } ],
    [ "linked", "Linked Hackatime", true, false, -> { linked.count } ],
    [ "editor_sent", "Editor sent time", true, false, -> { linked.where("projects.hackatime_seen_seconds > 0").count } ],
    [ "set_up", "Picked a Hackatime project", true, false, -> { linked.where("json_array_length(projects.hackatime_projects) > 0").count } ],
    [ "first_20", "Built their first 20 minutes", true, true, ->(through) { activities.completed.where(activity_date: ..through.to_date).distinct.count(:user_id) } ],
    [ "past_5h", "Past 5 hours", true, true, ->(through) { with_hours(5, through) } ],
    [ "past_10h", "Past 10 hours", true, true, ->(through) { with_hours(Program::HOURS_PER_REWARD, through) } ],
    [ "shipped", "Shipped", true, true, ->(through) { ships.where(created_at: ..through).distinct.count(:project_id) } ],
    [ "shipped_hours", "Hours shipped", true, true, ->(through) { ships.where(created_at: ..through).latest_per_project.sum(:hours).to_f } ],
    # The day.
    [ "builders", "Built that day", false, true, ->(through) { activities.where(activity_date: through.to_date, coded_seconds: 1..).count } ],
    [ "completed", "Hit 20 minutes that day", false, true, ->(through) { activities.completed.where(activity_date: through.to_date).count } ],
    [ "hours_day", "Hours that day", false, true, ->(through) { hours(activities.where(activity_date: through.to_date)) } ],
    [ "hours", "Hours in all", true, true, ->(through) { hours(activities.where(activity_date: Program::FIRST_STREAK_DATE..through.to_date)) } ],
    [ "on_streak", "On a streak", false, false, -> { participants.where(current_streak: 1..).count } ],
    # Together.
    [ "pairs", "Pairs", true, true, ->(through) { pairs.where(created_at: ..through).count } ],
    [ "pomodoros", "Pomodoros done together", true, true, ->(through) { BuddyPomodoro.where(pair_id: pairs.select(:id)).where.not(joined_at: nil).where(started_at: ..through).count } ],
    [ "shoutouts", "Shoutouts in Slack", true, true, ->(through) { rewards.where(key: %w[hours_shoutout streak_shoutout], created_at: ..through).count } ],
    # The bot.
    [ "nudges", "Nudges sent that day", false, true, ->(through) { nudges.delivered.real.where.not(kind: "cheer").where(sent_at: through.all_day).count } ],
    [ "nudges_worked", "Nudges that worked", false, true, ->(through) { nudges.delivered.real.where.not(kind: "cheer").where(sent_at: through.all_day, reward: 1).count } ],
    [ "cheers", "Cheers sent that day", false, true, ->(through) { nudges.delivered.cheers.where(sent_at: through.all_day).count } ],
    [ "muted", "Stopped Slack messages", true, false, -> { participants.where.not(slack_muted_at: nil).count } ]
  ].map { |args| Definition.new(*args) }.freeze

  KEYS = DEFINITIONS.map(&:key).freeze

  # Every number as of the end of `day`: the undated ones only for today.
  def self.values(day = Date.current)
    through = day.end_of_day
    DEFINITIONS.filter_map do |definition|
      value = definition.dated ? definition.value.call(through) : (definition.value.call if day == Date.current)
      [ definition.key, value ] unless value.nil?
    end.to_h
  end

  def self.snapshot!(day = Date.current)
    now = Time.current
    rows = values(day).map { |key, value| { day:, key:, value:, created_at: now, updated_at: now } }
    MetricSnapshot.upsert_all(rows, unique_by: [ :day, :key ]) if rows.any?
    rows.size
  end

  # Every day from `from` to today: the past as it was, today as it is now.
  def self.backfill!(from = Program::DATES.begin)
    (from..Date.current).sum { |day| snapshot!(day) }
  end

  # For the admin page: the days there are snapshots for, and each metric's value on each.
  def self.history
    rows = MetricSnapshot.where(day: Program::DATES.begin..).pluck(:key, :day, :value)
    days = rows.map(&:second).uniq.sort
    values = rows.each_with_object(Hash.new { |hash, key| hash[key] = {} }) { |(key, day, value), hash| hash[key][day] = value }
    [ days, values ]
  end

  # Everything below counts participants only (Armand, 2026-10-23: "do not count time from me"): nobody on the admin
  # list (User#listed_admin?) adds to any number, whether it's their own row or something they did.
  def self.participants = User.participants

  def self.projects = Project.where(user_id: participants.select(:id))

  def self.activities = StreakActivity.where(user_id: participants.select(:id))

  def self.ships = Ship.where(project_id: projects.select(:id))

  def self.nudges = Nudge.where(user_id: participants.select(:id))

  # A pair with an admin in it isn't counted, whoever the other half is.
  def self.pairs = Pair.where(first_project_id: projects.select(:id), second_project_id: projects.select(:id))

  def self.rewards = Reward.where(user_id: participants.select(:id)).or(Reward.where(pair_id: pairs.select(:id)))

  def self.linked
    participants.joins(:project).where.not(hackatime_uid: nil).where.not(hackatime_access_token: nil)
  end

  def self.with_hours(hours, through)
    activities.where(activity_date: Program::FIRST_STREAK_DATE..through.to_date).group(:user_id).sum(:coded_seconds)
                  .count { |_, seconds| seconds >= hours * 3600 }
  end

  def self.hours(scope) = (scope.sum(:coded_seconds) / 3600.0).round(1)

  private_class_method :participants, :projects, :activities, :ships, :nudges, :pairs, :rewards, :linked, :with_hours, :hours
end
