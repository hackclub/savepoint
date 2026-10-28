# Everyone who's set up, admins aside (D-032), ranked by hours today or in total (D-015): what the leaderboard page, the stairs on your
# project page and the bot's leaderboard nudges all read from, so they agree. Ties go to whoever pledged first.
#
# Once a day (LeaderboardSnapshotJob) everyone's total rank is noted on their project (week_rank, the column's old
# name), so the board can show who's moved since the last snapshot and the bot can say who passed you.
module Leaderboard
  SORTS = %w[today total].freeze

  Place = Data.define(:project, :rank, :above) do
    def user = project.user

    # Total hours between you and the one above you, in minutes. Nothing if you're first.
    def gap_minutes
      ((above.hours_logged - project.hours_logged) * 60).round if above
    end

    # Places you've moved since the last snapshot: up is positive, down negative, nil without a snapshot.
    def change
      was = project.week_rank
      was - rank if was && project.week_rank_on
    end
  end

  # What "today" means for one viewer: their own calendar date, in their time zone (D-015), or UTC when signed out.
  # Everyone's hours for that date are read by the same date key, so nobody's hours are converted.
  def self.date_for(user, now = Time.current)
    user ? user.local_date(now) : now.utc.to_date
  end

  # Set-up projects in order, with their users (and screenshots, for the board). Today is the viewer's `date`.
  def self.ranked(sort: "total", date: date_for(nil), projects: Project.includes(:user, screenshot_attachment: :blob))
    today = sort == "today"
    projects = projects.select { |project| project.set_up? && !project.user.listed_admin? }
    preload_board(projects, date)
    projects.sort_by { |project| [ -(today ? project.hours_today(today: date) : project.hours_logged), -project.hours_logged, project.id ] }
  end

  # One query for everyone's hours, one for their pairs and one for who has done a pomodoro together, instead of
  # a few queries for each person on the board (the project page drew about 1,200 for a real one).
  def self.preload_board(projects, date)
    return if projects.empty?

    user_ids = projects.map(&:user_id)
    activities = StreakActivity.where(user_id: user_ids)
    logged = activities.for_range(Program::FIRST_STREAK_DATE..).group(:user_id).sum(:coded_seconds)
    today = activities.for_range(date..date).group(:user_id).sum(:coded_seconds)
    projects.each { |project| project.preload_hours(logged: logged[project.user_id].to_i, today: today[project.user_id].to_i, on: date) }

    ActiveRecord::Associations::Preloader.new(records: projects, associations: { pair_as_first: :second_project, pair_as_second: :first_project }).call
    pairs = projects.filter_map { |project| project.pair_as_first || project.pair_as_second } # one record per project in a pair
    together = BuddyPomodoro.where(pair_id: pairs.map(&:id).uniq).where.not(joined_at: nil).distinct.pluck(:pair_id)
    pairs.each { |pair| pair.preload_together(together.include?(pair.id)) }
  end
  private_class_method :preload_board

  # Everyone's place, in order.
  def self.places(sort: "total", projects: nil, date: date_for(nil))
    ranked = projects ? ranked(sort:, date:, projects:) : ranked(sort:, date:)
    ranked.map.with_index(1) { |project, rank| Place.new(project:, rank:, above: (ranked[rank - 2] if rank > 1)) }
  end

  # Your place in total, or nil until you're set up.
  def self.place_of(project)
    places.find { |place| place.project == project }
  end

  # Note everyone's total rank as of now (see Project#week_rank).
  def self.snapshot!(today = Date.current)
    places(projects: Project.includes(:user)).each do |place|
      place.project.update_columns(week_rank: place.rank, week_rank_on: today)
    end
  end
end
