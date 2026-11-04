# What a reviewer checks a ship's claim against, beside the ship (D-063): the hours on each linked Hackatime project, the
# repository's facts and latest release, the Lapse sessions, who shipped it, the other accounts with the same repo or the
# same Slack account, and whether Stardance already has the repo. Each part is looked up when asked for and kept, and a
# failing service leaves a plain message in place of its part (Admin::ShipsController, AdminMcp get_ship). Nothing here is stored.
class Ship::Evidence
  CACHE_FOR = 5.minutes

  # at_ship and now are seconds from Save Point's start, nil when Hackatime didn't say.
  HackatimeRow = Data.define(:name, :at_ship, :now)
  # captured: the at-ship figures were kept when the ship was made. Otherwise they were asked just now, up to the ship.
  HackatimeHours = Data.define(:rows, :captured, :problem)
  # reason: why this account looks like the same person.
  Duplicate = Data.define(:user, :reason, :project)

  attr_reader :ship

  # commits: the Ship::Commits result already loaded for the page, whose earliest commit dates the release check.
  def initialize(ship, commits: nil)
    @ship = ship
    @commits = commits
  end

  def user = ship.project.user

  def hackatime
    @hackatime ||= load_hackatime
  end

  def repo
    @repo ||= Ship::RepoFacts.for(ship)
  end

  # The earliest commit between Save Point's start and the ship, nil without any.
  def first_commit_at
    @commits&.commits&.map(&:date)&.min
  end

  def release_predates? = repo.ok? && repo.release_predates?(first_commit_at, ship.project.hours_start)

  # { Ship::Lapses::Result }, and the share of the counted hours that is art.
  def lapses
    @lapses ||= Ship::Lapses.for(ship)
  end

  # D-105: the participant's Telescreen workbench, for their numeric Hackatime id (users.hackatime_uid) and the ship's linked
  # projects. Without a numeric id there is nothing to open for them, so the bare workbench opens. Built by Telescreen (D-114),
  # which the admin projects list uses too.
  def telescreen_url = Telescreen.hackatime_url_or_workbench(user, ship.hackatime_projects)

  def lapse_review_url = Telescreen.lapse_review_url(user)

  # Hackatime's trust level for them, read afresh when they have linked Hackatime (the stored one can be old), and the stored one
  # when Hackatime can't say.
  def trust_level
    return user.hackatime_trust_level.presence unless user.hackatime_linked?

    ::Hackatime.refresh_trust_level!(user)
  rescue ::Hackatime::NotLinked, ::Hackatime::Expired, ::Hackatime::Unavailable
    user.hackatime_trust_level.presence
  end

  # D-146: the code has to be in git. A line when the commits can't be read, the repository is empty, or it has no commit since the
  # hours began counting. nil when there are commits. The reviewer decides (the checklist never blocks), but the page says it in red.
  def no_code_in_git
    commits = @commits || Ship::Commits.for(ship)
    if !commits.ok?
      "The commits could not be read (#{commits.message}) Check by hand that the code is in git."
    elsif repo.ok? && repo.commits == 0
      "The repository is empty, so the code is not in git."
    elsif commits.commits.empty?
      "The repository has no commits since this project's hours began counting, so the code may not be in git."
    end
  end

  def other_ships
    @other_ships ||= Ship.joins(:project).where(projects: { user_id: user.id }).where.not(id: ship.id).includes(:project).order(created_at: :desc)
  end

  # Other accounts whose project has this repository.
  def same_repo
    @same_repo ||= begin
      key = Ship::EarlierShip.normalize(ship.repo_url)
      path = key.split("/", 2).last.to_s
      if path.blank? || !path.include?("/")
        []
      else
        candidates = Project.where.not(user_id: user.id).where("repo_url ILIKE ?", "%#{Project.sanitize_sql_like(path)}%").includes(:user)
        candidates.select { Ship::EarlierShip.normalize(it.repo_url) == key }.map { Duplicate.new(user: it.user, reason: "same repository", project: it) }
      end
    end
  end

  # Other accounts that look like the same person: the same Slack account. (Two accounts can't share a Hackatime account:
  # users.hackatime_uid is unique.)
  def same_person
    @same_person ||= user.slack_id.blank? ? [] : User.where(slack_id: user.slack_id).where.not(id: user.id).map { Duplicate.new(user: it, reason: "same Slack account", project: it.project) }
  end

  def duplicates = same_repo + same_person

  # D-063: the Stardance check. Part of the verdict form reads stardance_shipped? to turn Approve off.
  def stardance
    @stardance ||= Stardance.check(ship)
  end

  def stardance_shipped? = stardance.shipped?

  private
    def load_hackatime
      names = ship.hackatime_projects
      return HackatimeHours.new(rows: [], captured: false, problem: "No Hackatime project is linked to this ship.") if names.empty?
      return HackatimeHours.new(rows: [], captured: false, problem: "They haven't linked Hackatime, so there is no live figure.") unless user.hackatime_linked?

      captured = (ship.hackatime_seconds if ship.hackatime_seconds.is_a?(Hash))
      at_ship = captured || seconds_between(names, ship.created_at)
      now = seconds_between(names, Time.current)
      problem = "Hackatime couldn't be reached, so some figures are missing." if at_ship.nil? || now.nil?
      rows = names.map { |name| HackatimeRow.new(name:, at_ship: at_ship&.[](name)&.to_i, now: now&.[](name)&.to_i) }
      HackatimeHours.new(rows:, captured: captured.present?, problem:)
    end

    # { name => seconds } from the project's hours start (D-065) to the time, or nil when Hackatime can't say. Kept a few minutes.
    def seconds_between(names, time)
      Rails.cache.fetch([ "ship-evidence-hackatime", user.hackatime_uid, names, time.to_i / 300 ], expires_in: CACHE_FOR) do
        ::Hackatime.project_seconds(user, names, ship.project.hours_start..time)
      end
    rescue ::Hackatime::NotLinked, ::Hackatime::Expired, ::Hackatime::Unavailable
      nil
    end
end
