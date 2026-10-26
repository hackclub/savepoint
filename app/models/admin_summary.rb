# The numbers on the admin home (/admin) beside what's waiting: sign-ups, who built yesterday, the hours funnel from
# built to approved, the participants' funnel from sign-in to a claimed prize (ParticipantFunnel), and day by day
# (daily) the DAU, sign-ups and hours built, then the AdminInsights sections: who's on track for their goal, prize spend,
# who built on their sign-up day, ships and the review wait, and whether nudges worked. Participants only: nobody on the admin list adds to any of it (D-032,
# as Metric does).
class AdminSummary
  CACHE_FOR = 2.minutes

  def self.cached
    Rails.cache.fetch("admin_summary/v3", expires_in: CACHE_FOR) { new.to_h }
  end

  def to_h
    pace = AdminInsights::GoalPace.call
    funnel_now = ParticipantFunnel.run
    dates = growth.days.map(&:date)
    { signups: User.participants.count, signups_today: User.participants.where(created_at: Time.current.all_day).count,
      dau: growth.latest&.dau, dau_date: growth.latest&.date, daily:, participant_funnel: funnel_now, participant_waiting: ParticipantFunnel.waiting(funnel_now), **funnel,
      pace:, prize_spend: AdminInsights::PrizeSpend.call(pace), sign_up_day: AdminInsights::SignUpDay.call(dates:),
      ship_flow: AdminInsights::ShipFlow.call(dates:), nudge_results: AdminInsights::NudgeResults.call }
  end

  # One row for each finished day of Save Point so far (the days Growth models), oldest first: that day's DAU and how it
  # splits into Growth's active states (new, current, reactivated, resurrected), the participants who signed in that day
  # (UTC), and the hours they built. A day with nothing in it is 0, not missing.
  def daily
    signed_up = participants.where(created_at: Program::HACKATIME_START.beginning_of_day..).group("created_at::date").count
    seconds = StreakActivity.where(user_id: participants.select(:id), activity_date: Program::HACKATIME_START..).group(:activity_date).sum(:coded_seconds)
    growth.days.map do |day|
      { date: day.date, dau: day.dau, states: Growth::ACTIVE_STATES.index_with { |state| day.count_for(state) }.symbolize_keys, signups: signed_up.fetch(day.date, 0), hours: (seconds.fetch(day.date, 0) / 3600.0).round(1) }
    end
  end

  # Hours built on projects that no ship holds yet, hours in the ships in review, and hours approved. A ship holds every
  # hour logged up to it (Ship#hours), so what's unapproved is what's been built since the newest ship, and what's pending
  # is what the ship in review adds to the last approved one. Neither goes below 0.
  def funnel
    built = StreakActivity.where(user_id: participants.select(:id), activity_date: Program::FIRST_STREAK_DATE..).group(:user_id).sum(:coded_seconds)
    held = ships.latest_per_project.pluck(:project_id, :hours).to_h
    unapproved = projects.pluck(:id, :user_id).sum { |id, user_id| [ built.fetch(user_id, 0) / 3600.0 - held.fetch(id, 0), 0 ].max }
    approved_rows = ships.approved.pluck(:project_id, :approved_hours, :hours).group_by(&:first)
    approved = approved_rows.sum { |_, rows| rows.map { |_, approved, hours| approved || hours }.max }
    shipped_before = approved_rows.transform_values { |rows| rows.map(&:last).max }
    pending = ships.latest_per_project.pending.pluck(:project_id, :hours).sum { |id, hours| [ hours - shipped_before.fetch(id, 0), 0 ].max }
    { unapproved_hours: unapproved.to_f.round(1), pending_hours: pending.to_f.round(1), approved_hours: approved.to_f.round(1) }
  end

  private
    def participants = User.participants

    def projects = Project.where(user_id: participants.select(:id))

    def ships = Ship.where(project_id: projects.select(:id))

    def growth = @growth ||= Growth.new(participants_only: true)
end
