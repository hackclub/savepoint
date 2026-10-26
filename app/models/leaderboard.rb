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
    projects.select { |project| project.set_up? && !project.user.listed_admin? }.sort_by { |project| [ -(today ? project.hours_today(today: date) : project.hours_logged), -project.hours_logged, project.id ] }
  end

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
