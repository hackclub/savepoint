# The numbers on the public stats page (/stats): exact totals across everyone, and no names. Hours are from
# everyone's synced streak days (StreakActivity), so they lag Hackatime a little. Who's building each day, by group,
# is Growth's.
class PublicStats
  CACHE_FOR = 10.minutes

  # Streak lengths, grouped.
  STREAK_GROUPS = { "1 day" => 1..1, "2 days" => 2..2, "3–4" => 3..4, "5–6" => 5..6, "7–9" => 7..9, "10+" => 10.. }.freeze

  def self.cached
    Rails.cache.fetch("public_stats/v8", expires_in: CACHE_FOR) { new.to_h }
  end

  def to_h
    { generated_at: Time.current, day: program_day, days: Program.day(Program::ENDS_AT - 1)[:total], totals:, funnel:, daily:, growth: growth_data, streaks: }
  end

  private
    def program_day
      day = Program.day
      return 0 unless day
      Time.current >= Program::ENDS_AT ? day[:total] + 1 : day[:number]
    end

    # Seconds built per person since Hackatime time started counting.
    def seconds_by_user
      @seconds_by_user ||= StreakActivity.where(activity_date: Program::FIRST_STREAK_DATE..).group(:user_id).sum(:coded_seconds)
    end

    def users_with_hours(hours) = seconds_by_user.count { |_, seconds| seconds >= hours * 3600 }

    def totals
      {
        signed_up: User.participant_count,
        hours: (seconds_by_user.values.sum / 3600.0).round(1),
        shipped: Ship.distinct.count(:project_id),
        shipped_hours: Ship.latest_per_project.sum(:hours).to_f.round(1),
        prizes: picks_afforded
      }
    end

    # Whose hours cover the prize they picked.
    def picks_afforded
      Project.all.count { |project| project.afford?((seconds_by_user.fetch(project.user_id, 0) / 3600.0).round(1)) }
    end

    # Signed in to shipped, each step with how many got there.
    def funnel
      linked = User.joins(:project).where.not(hackatime_uid: nil).where.not(hackatime_access_token: nil)
      steps = {
        "Signed in" => User.count,
        "Pledged" => Project.count,
        "Linked Hackatime" => linked.count,
        "Picked their Hackatime project" => linked.where("json_array_length(projects.hackatime_projects) > 0").count,
        "Built their first 20 minutes" => StreakActivity.completed.distinct.count(:user_id),
        "Reached #{Program::HOURS_PER_REWARD / 2} hours" => users_with_hours(Program::HOURS_PER_REWARD / 2.0),
        "Reached #{Program::HOURS_PER_REWARD} hours" => users_with_hours(Program::HOURS_PER_REWARD),
        "Shipped" => Ship.distinct.count(:project_id)
      }
      first = steps.values.first
      steps.map { |label, count| { label:, count:, share: (count.fdiv(first) if first.positive?) } }
    end

    # Growth for everyone, worked out once: the page's DAU and the table's builders are the same numbers.
    def growth_data = @growth_data ||= Growth.new.to_h

    # Hours built each day of Save Point (every category, everyone), and how many built that day: Growth's DAU for the
    # day, not a second count, so the table and the DAU can't drift apart (coding time only, D-087; accounts sharing a
    # repo each count, D-090). Today's is as far as it's got.
    def daily
      seconds = StreakActivity.where(activity_date: Program::DATES, coded_seconds: 1..).group(:activity_date).sum(:coded_seconds)
      dau = growth_data[:days].to_h { |row| [ row[:date], row[:dau] ] }
      today = growth_data[:today]
      dau[today[:date]] = today[:dau] if today
      Program::DATES.map do |date|
        { date:, future: date > Date.current, builders: dau[date].to_i, hours: (seconds.fetch(date, 0) / 3600.0).round(1) }
      end
    end

    def streaks
      streakers = User.where(current_streak: 1..)
      lengths = streakers.pluck(:current_streak)
      {
        on_streak: lengths.size,
        longest: lengths.max,
        pairs: Pair.count,
        groups: STREAK_GROUPS.map { |label, range| { label:, people: lengths.count { |days| range.cover?(days) } } }
      }
    end
end
