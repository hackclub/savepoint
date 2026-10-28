# What someone signed up with at the end of onboarding (their game, its repo, the Hackatime project its hours come
# from, and the prize they're aiming for), and how far they've got setting up to build it.
class Project < ApplicationRecord
  include AirtableSynced

  # The columns the Airtable copy (AirtableFields.project) reads. Ships and orders mark it too, for its hours.
  AIRTABLE_COLUMNS = %w[name idea repo_url prize_key pace_minutes build_time signed_on jame_gam hackatime_projects].freeze

  # The prize you aim for is one of Prize::ALL (prize_key).
  PRIZE_KEYS = Prize::ALL.map(&:key).freeze
  PACES = [ 20, 45, 60, 120, 180 ].freeze
  # "Just enough" (just_enough_pace) and what it turns into as days pass: any multiple of 5 minutes up to the slowest preset.
  CUSTOM_PACES = 5..PACES.last
  BUILD_TIMES = [ "after school", "evening", "late night", "weekends" ].freeze

  # Still images only: the handbook refuses animated screenshots, so no GIF (D-030).
  SCREENSHOT_TYPES = %w[image/png image/jpeg image/webp].freeze
  SCREENSHOT_MAX_SIZE = 5.megabytes

  belongs_to :user
  has_many :ships, dependent: :destroy
  has_one :extension, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_one :pair_as_first, class_name: "Pair", foreign_key: :first_project_id, dependent: :destroy, inverse_of: :first_project
  has_one :pair_as_second, class_name: "Pair", foreign_key: :second_project_id, dependent: :destroy, inverse_of: :second_project
  # Shows on the leaderboard and your ship post.
  has_one_attached :screenshot

  # Renaming it to nothing puts back the name it had (your idea).
  normalizes :repo_url, with: ->(url) { Ship.with_scheme(url) }
  normalizes :name, with: ->(name) { name.strip.presence }
  normalizes :hackatime_projects, with: ->(names) { Array(names).map { |name| name.to_s.strip }.compact_blank.uniq }

  validates :prize_key, inclusion: { in: PRIZE_KEYS }, allow_nil: true
  validate :has_a_prize
  validates :pace_minutes, inclusion: { in: PACES }, unless: :custom_pace?
  validates :pace_minutes, numericality: { in: CUSTOM_PACES, only_integer: true }, if: :custom_pace?
  validate :pace_is_one_that_finishes_in_time, on: :update
  validates :build_time, inclusion: { in: BUILD_TIMES }
  validates :idea, :signed_on, presence: true
  validates :name, length: { maximum: 80 }
  # Only a new screenshot is checked, so a project with a GIF from before they were refused still saves.
  validate :screenshot_is_an_image, if: -> { attachment_changes["screenshot"] }
  validate :picking_hackatime_projects_you_have
  before_save :note_when_first_hackatime_project_picked, if: :will_save_change_to_hackatime_projects?
  # D-065: a moved hours start rebuilds every day from the new moment too.
  after_update_commit :refresh_streak, if: -> { saved_change_to_hackatime_projects? || saved_change_to_hours_start_override? }
  # D-066: a new repo or Hackatime project may be a jame gam game, so look again.
  after_update_commit :release_held_hours, if: -> { saved_change_to_hackatime_auto_linked? && hackatime_confirmed? }
  after_update_commit :check_jame_gam, if: -> { saved_change_to_hackatime_projects? || saved_change_to_repo_url? }
  validate :hours_start_override_in_range, if: :hours_start_override_changed?

  validates :repo_url, format: { with: Ship::URL, message: "should be a link, like https://github.com/you/game" },
                       allow_blank: true
  validate :repo_url_has_a_real_host

  # The project's name or idea, or who it's by (name, email or Slack), any part of it, for the admin's list.
  def self.search(query)
    pattern = "%#{sanitize_sql_like(query)}%"
    joins(:user).where("projects.name ILIKE :q OR projects.idea ILIKE :q OR " \
                       "users.name ILIKE :q OR users.email ILIKE :q OR users.slack_display_name ILIKE :q", q: pattern)
  end

  # Your game's name, or its idea.
  def title
    name || idea
  end

  # The first day you can build: the day Save Point does, or the day your hours start if later (hours_start, D-065: your
  # sign-up, a jame gam submission, or a reviewer's override), in your timezone like a streak day.
  def build_start
    [ Program::DATES.begin, StreakActivity.streak_date_for(hours_start, user.timezone) ].max
  end

  def build_day?(day)
    build_time != "weekends" || day.on_weekend?
  end

  # Your build days: the ones gone (to see how they went), then one per session of pace_minutes until the hours you
  # still need are in, from today on. Building on weekends, only Saturdays and Sundays count.
  def build_days(today: user.streak_today_date, to_go: hours_to_go, pace: pace_minutes)
    first = [ today, build_start ].max
    days = (build_start...first).select { |day| build_day?(day) }
    sessions = (to_go * 60.0 / pace).ceil
    sessions = 1 if sessions.zero? && days.empty?
    day = first
    added = 0
    while added < sessions
      if build_day?(day)
        days << day
        added += 1
      end
      day += 1
    end
    days
  end

  def finish_on(**)
    build_days(**).last
  end

  # How many days you've left to build in, today included, up to the deadline.
  def days_left(today: user.streak_today_date)
    (([ today, build_start ].max)..deadline).count { |day| build_day?(day) }
  end

  # Whether building `minutes` a day on the days left covers the hours you still need (always, once you have them).
  def pace_feasible?(minutes, today: user.streak_today_date)
    hours_to_go.zero? || minutes * days_left(today:) >= hours_to_go * 60
  end

  # Any 5-minute multiple, not one of the presets: what "Just enough" stores.
  def custom_pace?
    !PACES.include?(pace_minutes) && pace_minutes.to_i % 5 == 0
  end

  # The minutes a day that get you there a day before the deadline (that day's the buffer), up to the next 5: nil once
  # you have the hours. With a day or less left it's all of what's left.
  def just_enough_pace(today: user.streak_today_date)
    return if hours_to_go.zero?

    days = [ days_left(today:) - 1, 1 ].max
    [ [ (hours_to_go * 60.0 / days / 5).ceil * 5, CUSTOM_PACES.first ].max, CUSTOM_PACES.last ].min
  end

  def feasible_paces(today: user.streak_today_date)
    PACES.select { |minutes| pace_feasible?(minutes, today:) }
  end

  # Which day of building it is: 1 on the first, counting up from there.
  def day_number(today: Date.current)
    [ (today - build_days.first).to_i + 1, 1 ].max
  end

  # What a new project's pace is: the smallest of PACES that covers the prize's daily pace.
  def self.pace_for(prize)
    PACES.find { |minutes| minutes >= prize.pace_minutes } || PACES.last
  end

  # The prize you're aiming for, from Prize::ALL, if you picked one that way.
  def chosen_prize
    Prize.find(prize_key) if prize_key
  end

  # "Aseprite": the short name of what you're building towards.
  def prize_short
    chosen_prize&.name
  end

  # "an Aseprite": the short name with its article, for a sentence.
  def prize_with_article
    chosen_prize&.with_article
  end

  # "Aseprite"
  def prize_name
    chosen_prize&.name
  end

  # What you picked, as the shop names it. The same as prize_name: a prize in Prize::ALL has one name.
  def prize_configuration
    prize_name
  end

  # The hours your pick takes (its hours in Prize::ALL), and how many more that is than you've built.
  def hours_needed
    (chosen_prize || Prize.find(prize_key_in_database)).hours
  end

  def hours_to_go
    [ (hours_needed - hours_unspent_logged).round(1), 0 ].max
  end

  # Your hours, less what you've spent, cover your pick.
  def afford?(hours = hours_logged)
    hours - hours_spent >= hours_needed
  end

  # The hours your ships got approved with: the most of any approved ship, since each counts every hour logged up to
  # it (Ship#hours), and an admin can approve fewer (Ship#approved_hours). A later ship's approval is the earlier one
  # plus the new hours (D-097), so the latest is also the largest. The shop spends them like money (Order).
  def hours_approved
    ships.select(&:approved?).map { |ship| ship.approved_hours || ship.hours }.max.to_f
  end

  # What you've spent in the shop (orders made, not one being made), and what's left of your approved hours to spend.
  # Summed in the database, not from the loaded orders: a claim checks this under the project's lock (Order#save), and
  # the lock's reload would otherwise leave a stale, empty orders cache behind for whoever built the order.
  def hours_spent
    orders.sum(:hours).to_f
  end

  def hours_to_spend
    [ (hours_approved - hours_spent).round(2), 0 ].max
  end

  # The hours you've logged that haven't been spent: what's working towards the next thing.
  def hours_unspent_logged
    [ hours_logged - hours_spent, 0 ].max
  end

  # You've claimed the prize you're aiming for already.
  def goal_claimed?
    chosen_prize.present? && orders.any? { |order| order.persisted? && order.prize_key == prize_key }
  end

  # Your approved hours to spend cover your goal, and you haven't claimed it: it's yours to claim.
  def goal_reached?
    chosen_prize.present? && !goal_claimed? && hours_to_spend >= hours_needed
  end

  # The "you've earned it" popup shows once per goal: when goal_reached? and it wasn't shown for this goal yet.
  def goal_reached_popup?
    goal_reached? && goal_reached_seen_key != prize_key
  end

  def goal_reached_seen!
    update_column(:goal_reached_seen_key, prize_key)
  end

  # The prize to offer when your goal's reached: the cheapest one costing more than your goal that you haven't claimed.
  # Nothing when your goal is the dearest.
  def upsell_prize
    goal = chosen_prize or return
    claimed = orders.select(&:persisted?).filter_map(&:prize_key)
    Prize::ALL.select { |prize| prize.cost > goal.cost && claimed.exclude?(prize.key) }.min_by { |prize| [ prize.cost, prize.hours ] }
  end

  # Setting up, in order: link Hackatime, then which Hackatime project this is, add a repo (or say you'll add it before
  # you ship) and bring a buddy (or skip it).
  SETUP_STEPS = %w[hackatime hackatime_project repo buddy].freeze
  # You're set up once Hackatime's linked. Which Hackatime project this is can wait: with nothing on Hackatime since it
  # started counting there's nothing to pick yet, and the first new project you log time on links itself
  # (auto_link_hackatime_project). The repo and a buddy can wait too.
  REQUIRED_STEPS = %w[hackatime].freeze

  def step_done?(step)
    case step
    when "hackatime" then hackatime_linked?
    when "hackatime_project" then hackatime_projects.any?
    when "repo" then (repo_url.present? && errors[:repo_url].none?) || repo_later?
    when "buddy" then buddy.present? || buddy_invited? || buddy_skipped?
    end
  end

  # The Hackatime project needs Hackatime linked first.
  def step_locked?(step)
    step == "hackatime_project" && !hackatime_linked?
  end

  # Steps you can still open: anything not done, the Hackatime projects (to change which are linked) and the repo
  # while it's only promised for later.
  def step_open?(step)
    SETUP_STEPS.include?(step) && !step_locked?(step) &&
      (!step_done?(step) || step == "hackatime_project" || (step == "repo" && repo_url.blank?) || (step == "buddy" && buddy.nil?))
  end

  def required_steps_done
    REQUIRED_STEPS.count { |step| step_done?(step) }
  end

  # Optional steps you haven't done, put off or skipped (a Hackatime project with nothing to pick yet isn't one).
  def optional_steps_left
    (SETUP_STEPS - REQUIRED_STEPS).count { |step| !step_settled?(step) }
  end

  # What setup needs: Hackatime linked. That's what unlocks shipping and the leaderboard.
  def set_up?
    required_steps_done == REQUIRED_STEPS.size
  end

  # You've been through every step: done, put off or skipped. Until then your project page walks you through them,
  # one at a time, and once you're through it turns into your schedule (and the bot congratulates you).
  def setup_finished?
    set_up? && SETUP_STEPS.all? { |step| step_settled?(step) }
  end

  # Setup finished and nothing put off: the repo has a link. A skipped buddy or a pending invite counts as done. Then
  # the project page has no setup card.
  def setup_all_done?
    setup_finished? && !repo_put_off?
  end

  # You said "later" to the repo and haven't added it.
  def repo_put_off?
    repo_url.blank? && repo_later?
  end

  # Done, or (your Hackatime project) nothing to pick yet, since it links itself.
  def step_settled?(step)
    step_done?(step) || (step == "hackatime_project" && waiting_for_hackatime_project?)
  end

  # D-084: a link the person picked by hand is confirmed (D-091: however it is named). One that linked itself
  # (hackatime_auto_linked) isn't until they press Yes or pick another; its time is synced but held
  # (StreakActivity#unconfirmed_seconds).
  def hackatime_confirmed? = !hackatime_auto_linked?

  # Hours count once Hackatime knows which project this is.
  def tracking?
    hackatime_linked? && hackatime_projects.any?
  end

  # Hackatime's linked but has nothing since it started counting to pick from, so the first project you log time on
  # will link itself. Only known once available_hackatime_projects has been asked for.
  def waiting_for_hackatime_project?
    hackatime_linked? && hackatime_projects.none? && available_hackatime_projects&.none?
  end

  # D-086: Hackatime's linked and has projects of yours (when we last asked it), but none is picked, and the page isn't
  # waiting on a first heartbeat. Their hours can't count until they pick one. Not in the first half hour after linking,
  # when the project they build on is still likely to link itself (D-048).
  def needs_to_pick_hackatime_project?
    hackatime_linked? && hackatime_projects.none? && hackatime_seen_count.to_i.positive? && !awaiting_first_heartbeat? &&
      (user.hackatime_linked_at.nil? || user.hackatime_linked_at <= 30.minutes.ago)
  end

  # D-078: Hackatime's linked but no time has ever arrived from you: none seen when we asked it, and no coded day synced.
  # The project page then waits for your first heartbeat.
  def awaiting_first_heartbeat?
    hackatime_linked? && hackatime_seen_seconds.to_i.zero? && user.streak_activities.where("coded_seconds > 0").none?
  end

  # Asks Hackatime now whether your first time has arrived (and links the project it's on, as the project page does),
  # and says whether it has. Hackatime is asked at most once per FIRST_HEARTBEAT_EVERY per person; in between, the
  # last answer stands.
  FIRST_HEARTBEAT_EVERY = 30.seconds

  def first_heartbeat_arrived?
    Rails.cache.fetch([ "first-heartbeat", user_id ], expires_in: FIRST_HEARTBEAT_EVERY) do
      available = Hackatime.projects(user, refresh: true)
      self.available_hackatime_projects = available
      auto_link_hackatime_project(available)
      !awaiting_first_heartbeat?
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      false
    end
  end

  def pair
    pair_as_first || pair_as_second
  end

  # Who you're building alongside, if anyone.
  def buddy
    pair&.buddy_of(self)
  end

  # A new invite code: random, so the link says nothing about who you are.
  def self.new_buddy_code
    loop do
      code = SecureRandom.alphanumeric(8).downcase
      return code unless exists?(buddy_code: code)
    end
  end

  # Your invite link's code (/b/<code>), made the first time it's asked for.
  def buddy_code!
    return buddy_code if buddy_code.present?

    code = self.class.new_buddy_code
    update_column(:buddy_code, code) # just the code: whatever else is mid-edit (and maybe invalid) isn't saved
    code
  end

  # Pairs you up with another project, if neither of you has a buddy yet. Returns the pair: saved, or with why not.
  def pair_with(other)
    Pair.create(first_project: other, second_project: self, started_on: Date.current)
  end

  # Linking Hackatime is yours, not the project's: it's who you are on Hackatime.
  def hackatime_linked?
    user.hackatime_linked?
  end

  # The Hackatime projects you can link: the ones Hackatime says you've logged time on. Set before linking one (and
  # on your project page, while you haven't).
  attr_reader :available_hackatime_projects

  # The names the picker offers (Hackatime.pickable_projects, D-089), which include projects with time only before the
  # start. They may be picked even though available_hackatime_projects, which counts since the start, lacks them. Nil when
  # Hackatime couldn't say.
  attr_reader :pickable_hackatime_names

  # Asks Hackatime for what the picker lists and what counts, ahead of linking a pick. Either left nil when Hackatime
  # can't say (D-103).
  def load_hackatime_picks
    self.available_hackatime_projects = begin
      Hackatime.projects(user)
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      nil
    end
    @pickable_hackatime_names = begin
      Hackatime.pickable_projects(user).map(&:name) if available_hackatime_projects
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      nil
    end
  end

  HACKATIME_NO_ANSWER = "Hackatime didn't answer. Try again in a moment."

  def hackatime_no_answer?
    errors.of_kind?(:base, HACKATIME_NO_ANSWER)
  end

  # Whenever we ask Hackatime, what it said is kept too: how many projects and their seconds. Nothing's linked until
  # someone picks one, so without this "never set up the editor" and "coding on a project that isn't linked" look the
  # same. A failed ask sets nil, which says nothing, so it doesn't overwrite what we last saw.
  def available_hackatime_projects=(projects)
    @available_hackatime_projects = projects
    return if projects.nil? || !persisted?

    update_columns(hackatime_seen_count: projects.size, hackatime_seen_seconds: projects.sum(&:seconds), hackatime_seen_at: Time.current)
  end

  # The Hackatime projects you ticked: these become the linked ones. Any you hadn't linked before have to be
  # ones Hackatime has.
  def hackatime_project_names=(names)
    names = Array(names).map { |name| name.to_s.strip }.compact_blank.uniq
    @picked_hackatime_projects = names
    self.hackatime_projects = names
    self.hackatime_auto_linked = false
  end

  # The Hackatime project you build on links itself (D-048). The first time we look after you link Hackatime, we note
  # the projects you already have there and the seconds on each (that's all this does then). After that, the project
  # that gained the most time since then is linked for you, until you keep it or change it, and the bot DMs you to say
  # so. A project you didn't have counts all its time as gained. One you did have counts what it gained since, because
  # a continued game keeps its old Hackatime name. Hackatime's seconds run from Program::HACKATIME_START, and everyone
  # signed within a day of it, so a project noted before seconds were kept counts as 0 then: all its time is new.
  # D-064: a Hackatime project linked to a repo (on Hackatime) that isn't this project's repo is another game, so it's
  # left out. That needs both repos, so Hackatime is only asked when this project has one; if either side has none, or
  # Hackatime can't say, nothing is left out.
  # Returns its name if it linked one just now.
  AUTO_LINKED_DM = "Hackatime has new time from you on *%{hackatime_project}*, so it's linked to *%{title}* now! Your hours " \
                   "count from here. Not the right one? Change it on your project page :)"

  def auto_link_hackatime_project(available)
    return unless hackatime_linked? && hackatime_projects.none?

    if hackatime_baseline.nil?
      update_columns(hackatime_baseline: available.map(&:name), hackatime_baseline_seconds: available.to_h { |project| [ project.name, project.seconds ] })
      return
    end

    gained = ->(project) { project.seconds - (hackatime_baseline_seconds&.dig(project.name) || 0) }
    newest = without_other_repos(available.select { |project| gained.(project).positive? }).max_by(&gained)
    return unless newest

    update_columns(hackatime_projects: [ newest.name ], hackatime_auto_linked: true, hackatime_picked_at: hackatime_picked_at || Time.current)
    refresh_streak
    check_jame_gam
    dm_about_auto_link(newest.name)
    newest.name
  end

  # `candidates` without the Hackatime projects whose repo on Hackatime differs from repo_url (D-064).
  def without_other_repos(candidates)
    return candidates if candidates.empty?

    repos = hackatime_repo_links
    candidates.reject { |project| other_repo?(project.name, repos) }
  end

  # The repo links Hackatime has for your projects, { name => repo link }, to compare with repo_url (D-064). Hackatime is
  # only asked when this project has a repo; if it can't say, there are none.
  def hackatime_repo_links
    self.class.hackatime_repo_links(user, repo_url)
  end

  # Whether Hackatime links the project `name` to a repo other than repo_url, given `repos` (hackatime_repo_links). Needs
  # both links, and they must differ once normalized.
  def other_repo?(name, repos)
    self.class.other_repo?(repo_url, name, repos)
  end

  # The same two checks for a repo link that isn't on a saved project yet (onboarding types it before the project exists).
  def self.hackatime_repo_links(user, repo_url)
    return {} if repo_url.blank?

    Hackatime.repo_urls(user)
  rescue Hackatime::Unavailable, Hackatime::Expired, Hackatime::NotLinked
    {}
  end

  def self.other_repo?(repo_url, name, repos)
    return false if repo_url.blank? || repos[name].blank?

    Ship::EarlierShip.normalize(repos[name]) != Ship::EarlierShip.normalize(repo_url)
  end

  # Hours on your linked Hackatime projects since your hours start (hours_start, D-065), to a
  # tenth, from your synced streak days: the same days your weekly hours and the leaderboard count, so they always
  # agree. Nothing until Hackatime's linked and a project picked. `refresh` brings the days up to date from Hackatime
  # first (what we last saw, if it can't be reached right now).
  def hours_logged(refresh: false)
    return 0 unless tracking?

    @hours_logged = nil if refresh
    @hours_logged ||= begin
      refresh_hours if refresh
      user.hours_in(Program::FIRST_STREAK_DATE..)
    end
  end

  # D-065: Hackatime time counts from the later of Save Point's start and your sign-up, unless a reviewer set a start on
  # this project (hours_start_override). D-066: a jame gam submission of this game moves it later still, whatever its review
  # status. Nothing counts earlier, so the streak sync clips every span here and the ship's hours, the Airtable dates and
  # the site's totals follow.
  def hours_start = hours_start_override || [ Program::STARTS_AT, user.created_at, jame_gam_submitted_at ].compact.max

  # Where hours_start comes from: :override (a reviewer's), :jame_gam (the game was submitted there), :sign_up (they joined
  # after the launch) or :launch.
  def hours_start_source
    if hours_start_override then :override
    elsif jame_gam_submitted_at && jame_gam_submitted_at > [ Program::STARTS_AT, user.created_at ].max then :jame_gam
    elsif user.created_at > Program::STARTS_AT then :sign_up
    else :launch
    end
  end

  # D-066: looks the game up in the jame gam's Submission Form and stores the latest matching submission. An error or a
  # missing token changes nothing: a stored time is never cleared because Airtable was out of reach. A moved time rebuilds
  # the person's days, the same as a reviewer's override does.
  def refresh_jame_gam!(result = JameGam::Submissions.for(user))
    unless result.ok?
      Rails.logger.warn("Jame gam lookup for project #{id} failed: #{result.message}")
      return result
    end

    latest = result.submissions.select { it.matches?(self) }.max_by(&:submitted_at)
    moved = latest&.submitted_at&.to_f&.round(3) != jame_gam_submitted_at&.to_f&.round(3)
    update_columns(jame_gam_submitted_at: latest&.submitted_at, jame_gam_submission_id: latest&.id, jame_gam_review_status: latest&.review_status)
    refresh_streak if moved
    result
  end

  # Hours on one calendar date, as of the last streak sync. The leaderboard passes the viewer's own today (Leaderboard.date_for).
  def hours_today(today: Program.today)
    user.hours_in(today..today)
  end

  # As of the last sync (see User::Streakable).
  def streak = user.current_streak

  # D-096: at this many unshipped hours the project page and the bot ask you to ship.
  SHIP_PROMPT_HOURS = 5

  # D-096: the hours you have logged (hours_logged, the figure the page shows) less the hours of your latest ship that
  # is still standing, in review or approved. A ship sent back for changes or rejected doesn't count as shipped. Before
  # any ship it's all of them. Never below 0.
  def unshipped_hours
    [ (hours_logged.to_f - latest_standing_ship&.hours.to_f).round(1), 0 ].max
  end

  # The newest ship that counts as shipped for unshipped_hours: in review, awaiting its fraud check, or approved.
  def latest_standing_ship
    ships.select { it.pending? || it.approved? }.max_by(&:id)
  end

  def ship_prompt_due? = unshipped_hours >= SHIP_PROMPT_HOURS

  # D-099: the hours a participant with an approved ship needs since it before they can ship again.
  SHIP_MINIMUM_NEW_HOURS = 1

  # The newest approved ship: "your last ship" for the new-hours minimum (D-099) and the what-changed commit list (D-100).
  def latest_approved_ship
    ships.select(&:approved?).max_by(&:id)
  end

  # D-099: the hours still needed before the next ship, 0 when it can go now. New hours are the hours_logged a ship stores
  # (Ship#hours) less the latest approved ship's. No approved ship yet (the first ship) means no minimum, and a newest ship
  # sent back for changes is always free to go again: that is the fix, not a new ship (D-049).
  def ship_hours_needed
    approved = latest_approved_ship
    return 0 if approved.nil? || ships.select(&:persisted?).max_by(&:id).changes_needed?

    [ (SHIP_MINIMUM_NEW_HOURS - (hours_logged.to_f - approved.hours.to_f)).round(1), 0 ].max
  end

  def ship_waiting? = ship_hours_needed.positive?

  # Once a ship's approved (which is once it has passed its fraud check, D-063).
  def shipped?
    ships.any? { |ship| ship.status == "approved" }
  end

  # The ship that isn't decided: waiting for a review or for its fraud check. To the participant both are "in review".
  def ship_in_review
    ships.pending.order(:created_at).last
  end

  # The newest ship, when an admin rejected it for good (D-063): there's no shipping again.
  def ship_rejected
    latest = ships.order(:id).last
    latest if latest&.rejected?
  end

  # When you have to ship by: Save Point's last day (D-017), everyone's.
  def deadline
    Program::DATES.end
  end

  # Save Point's days, for you: the program's, running on to your deadline if it moved. Nudges go by this.
  def program_dates
    Program::DATES.begin..deadline
  end

  # Ship closes at the end of the deadline where you are, plus Program::SHIP_GRACE_DAYS nobody's told about.
  def ship_cutoff
    (deadline + Program::SHIP_GRACE_DAYS).in_time_zone(user.time_zone).end_of_day
  end

  # Until the cutoff, unless an admin banned the account or rejected the newest ship for good (D-063).
  def may_ship?(now: Time.current)
    now <= ship_cutoff && !user.banned? && ship_rejected.nil?
  end

  # Nobody can ask for more time: there are no extensions in Save Point.
  def extension_requestable?(now: Time.current)
    false
  end

  # Shipping: what you submit becomes your project's name and repo too, and the screenshot you pick is kept with the
  # ship. D-016: every ship needs a new screenshot, so the project's own is never reused.
  def ship!(params)
    upload = params.delete(:screenshot)
    ship = ships.build(params.merge(hackatime_projects:, hours: hours_logged))
    ship.capture_hackatime_seconds
    ship.screenshot.attach(upload) if upload.present?

    if ship.save
      screenshot.attach(ship.screenshot.blob) if upload.present?
      update!(name: ship.title, repo_url: ship.repo_url)
    end
    ship
  end

  private
    # The first time a Hackatime project is linked (picked, or linked by itself): a later change keeps the time.
    def note_when_first_hackatime_project_picked
      self.hackatime_picked_at ||= Time.current if hackatime_projects.present?
    end

    def refresh_streak
      user.refresh_streak!
    end

    # D-084: confirmed (Yes, or picked by hand): the held time counts now, then the sync catches up.
    def release_held_hours
      StreakActivity.release_held!(user)
      user.recalculate_streak!
      user.sync_streak!
    end

    def check_jame_gam
      JameGamRefreshJob.perform_later(id)
    end

    # D-065: a reviewer's start can't be before Save Point or in the future.
    def hours_start_override_in_range
      return unless hours_start_override

      errors.add(:hours_start_override, "can't be before Save Point began (#{Program::STARTS_AT.utc.strftime("%b %-d, %H:%M")} UTC)") if hours_start_override < Program::STARTS_AT
      errors.add(:hours_start_override, "can't be in the future") if hours_start_override > Time.current
    end

    # A DM from the bot, if they're on Slack and haven't stopped its messages. Noted as its latest DM as it's
    # queued, so a nudge or cheer in the same minute holds off.
    def dm_about_auto_link(hackatime_project)
      return if user.slack_id.blank? || user.slack_muted_at.present?
      user.slack_dmed!
      text = format(AUTO_LINKED_DM, hackatime_project: SlackText.escape(hackatime_project), title: SlackText.escape(title))
      SlackMessageJob.perform_later(user.slack_id, text,
                                    link: [ "Open Save Point", "#{Rails.configuration.x.app_url}/project" ])
    end

    def refresh_hours
      user.sync_streak_now!
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      nil
    end

    def picking_hackatime_projects_you_have
      return if @picked_hackatime_projects.nil?
      return errors.add(:hackatime_projects, "need one picked") if @picked_hackatime_projects.empty?

      unknown = @picked_hackatime_projects - hackatime_projects_was.to_a
      if available_hackatime_projects.nil? && pickable_hackatime_names.nil?
        # D-103: nil is Hackatime not answering (an empty list is an answer), so it can't say the pick is missing.
        errors.add(:base, HACKATIME_NO_ANSWER) if unknown.any?
        return
      end

      unknown -= available_hackatime_projects.to_a.map(&:name)
      unknown -= pickable_hackatime_names.to_a # D-089: the picker lists projects with earlier time only, so they can be picked
      errors.add(:hackatime_projects, "don't include #{unknown.to_sentence} on Hackatime") if unknown.any?
    end

    # A pace you pick has to get you to your prize by the deadline, when any pace can.
    def pace_is_one_that_finishes_in_time
      return unless pace_minutes_changed? && tracking? && feasible_paces.any? && !pace_feasible?(pace_minutes)

      errors.add(:pace_minutes, "is too slow to finish by #{deadline.strftime("%b %-d")}")
    end

    def has_a_prize
      errors.add(:prize_key, "needs a prize") if prize_key.blank?
    end

    # A repo link needs a host with a dot ("github.com"), so "junk" (which gets https:// in front) is turned down.
    def repo_url_has_a_real_host
      return if repo_url.blank? || errors[:repo_url].any?

      host = URI.parse(repo_url).host.to_s
      errors.add(:repo_url, "should be a link, like https://github.com/you/game") unless host.include?(".")
    rescue URI::InvalidURIError
      errors.add(:repo_url, "should be a link, like https://github.com/you/game")
    end

    def screenshot_is_an_image
      return unless screenshot.attached?

      if !SCREENSHOT_TYPES.include?(screenshot.blob.content_type)
        errors.add(:screenshot, "should be a still PNG, JPEG or WebP, not a GIF")
      elsif screenshot.blob.byte_size > SCREENSHOT_MAX_SIZE
        errors.add(:screenshot, "should be under 5 MB")
      end
    end
end
