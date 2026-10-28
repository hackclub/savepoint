# The numbers on the admin home (/admin) beside what's waiting: sign-ups, who built yesterday, the hours funnel from
# built to approved, the participants' funnel from sign-in to a claimed prize (ParticipantFunnel), and day by day
# (daily) the DAU, sign-ups and hours built, then the AdminInsights sections: who's on track for their goal, prize spend,
# who built on their sign-up day, ships and the review wait, and whether nudges worked. Participants only: nobody on the admin list adds to any of it (D-032,
# as Metric does).
class AdminSummary
  CACHE_FOR = 2.minutes

  def self.cached
    Rails.cache.fetch("admin_summary/v9", expires_in: CACHE_FOR) { new.to_h }
  end

  def to_h
    pace = AdminInsights::GoalPace.call
    funnel_now = ParticipantFunnel.run
    dates = growth.days.map(&:date)
    sign_up_days = AdminInsights::SignUpDay.call(dates: Program::DATES.cover?(Date.current) ? [ *dates, Date.current ] : dates)
    { signups: User.participants.count, signups_today: User.participants.where(created_at: Time.current.all_day).count,
      dau: dau_today, dau_unconfirmed: dau_unconfirmed_today, shared_games: shared_games, dau_on_site: dau_on_site(site_days), daily:, today_row:, site_days:, participant_funnel: funnel_now, participant_waiting: ParticipantFunnel.waiting(funnel_now), **funnel,
      pace:, prize_spend: AdminInsights::PrizeSpend.call(pace), sign_up_day: sign_up_days.first(dates.size), sign_up_today: (sign_up_days[dates.size]&.merge(partial: true)),
      ship_flow: AdminInsights::ShipFlow.call(dates:), nudge_results: AdminInsights::NudgeResults.call }
  end

  # D-092: participants who built Growth::ACTIVE_SECONDS or more today, the America/New_York calendar day from midnight (CodedBucket),
  # counting confirmed links only (D-084). D-087: only time Hackatime files under coding counts. D-090: accounts that share
  # a repo each count. (D-086 counted a rolling 24 hours.)
  def dau_today
    builders_today.count { |_, counted, _| counted >= Growth::ACTIVE_SECONDS }
  end

  # D-084: participants whose only time today is on an auto-linked Hackatime project nobody has confirmed. They aren't in dau_today.
  def dau_unconfirmed_today
    builders_today.count { |_, counted, held| counted < Growth::ACTIVE_SECONDS && held >= Growth::ACTIVE_SECONDS }
  end

  # D-087: each pair of participants' projects that share a repo, for the admin to judge: one person on two accounts, or a team.
  # { project_id:, user_id:, title:, name: (their public name), other_* the same for the other }.
  def shared_games
    SharedGames.pairs(user_ids: participants.select(:id)).map do |pair|
      { project_id: pair.project.id, user_id: pair.project.user_id, name: pair.project.user.public_name, title: pair.project.title,
        other_project_id: pair.other.id, other_user_id: pair.other.user_id, other_name: pair.other.user.public_name, other_title: pair.other.title }
    end
  end

  # Of today's builders, how many also opened the site; nil until any visit has been recorded.
  def dau_on_site(recorded)
    recorded.fetch(Date.current, 0) if recorded.any?
  end

  # How many of each day's builders also opened the site (D-076), by date. Nothing before the first day it was recorded: a
  # missing date is unknown, not 0.
  def site_days
    first = SiteDay.minimum(:date)
    return {} unless first
    SiteDay.builders_by_date.select { |row| row[:date] >= first }.to_h { |row| [ row[:date], row[:on_site] ] }
  end

  # One row for each finished day of Save Point so far (the days Growth models), oldest first: that day's DAU and how it
  # splits into Growth's three groups (new, built the day before too, back after days off), the participants who signed in that day
  # (UTC), and the hours they built. A day with nothing in it is 0, not missing.
  def daily = rows_for(growth.days)

  # Today as far as it's got (D-082): the same row as a finished day's, marked partial so the charts draw it as unfinished.
  # D-092: its builders are the tile's (the Eastern day, from the 5-minute pieces), not the streak days' (each person's own 2am
  # to 2am), and its date is the Eastern one, so the last column of the charts and the DAU tile are one number. Each is put in the state they'd have today
  # given the finished days they built. Nil outside the days of Save Point.
  def today_row
    today = day_start.to_date
    return unless Program::DATES.cover?(today) && today >= Program::HACKATIME_START

    states = Growth::ACTIVE_STATES.index_with(0)
    builders_today.each do |user_id, counted, _|
      next if counted < Growth::ACTIVE_SECONDS

      state = Growth.state_on([ *growth.active_dates(user_id).select { |date| date < today }, today ], today)
      states[state] += 1
    end
    row = rows_for([ Growth::Day.new(date: today, counts: states, transitions: {}) ]).first
    row.merge(partial: true, states: states.symbolize_keys)
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
    # Midnight starting today for the DAU: Armand's ruling, Eastern time, not UTC.
    def day_start = Time.current.in_time_zone("America/New_York").beginning_of_day

    # Per builder (D-090: accounts that share a repo each count): [id, coding seconds that count, coding seconds held],
    # since midnight today, Eastern time (D-092).
    def builders_today
      @builders_today ||= begin
        CodedBucket.totals_since(day_start, participants.select(:id)).group_by { |user_id, _, _| user_id }
                   .map { |id, rows| [ id, rows.sum { |row| row[1].to_i }, rows.sum { |row| row[2].to_i } ] }
      end
    end

    def rows_for(days)
      signed_up = participants.where(created_at: Program::HACKATIME_START.beginning_of_day..).group("created_at::date").count
      seconds = StreakActivity.where(user_id: participants.select(:id), activity_date: Program::HACKATIME_START..).group(:activity_date).sum(:coded_seconds)
      on_site = site_days
      days.map do |day|
        { date: day.date, on_site: on_site[day.date], dau: day.dau, states: Growth::ACTIVE_STATES.index_with { |state| day.count_for(state) }.symbolize_keys, signups: signed_up.fetch(day.date, 0), hours: (seconds.fetch(day.date, 0) / 3600.0).round(1) }
      end
    end

    def participants = User.participants

    def projects = Project.where(user_id: participants.select(:id))

    def ships = Ship.where(project_id: projects.select(:id)).where.not(status: "superseded")

    def growth = @growth ||= Growth.new(participants_only: true)
end
