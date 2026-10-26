# Everything a nudge needs to know about someone right now: where they are in their local day, which bucket they're
# in, and the values the bot's copy fills in. Hours, streaks and who else built come from their synced streak days
# (StreakActivity), brought up to date from Hackatime by refresh!. For a cheer, built_on is the streak day it's for.
class Nudge::Context
  # No streak day with any building in this many days makes you lapsed.
  LAPSED_AFTER_DAYS = 2
  # Social copy needs enough people for the number to mean something.
  MIN_PEERS = 3
  # A setup nudge for the same step waits this long before saying it again.
  SETUP_EVERY = 3.days
  # Overtake copy only when the one above you is within a session's reach.
  GAP_MINUTES = 60

  attr_reader :user, :project, :now, :local_now, :built_on

  def initialize(user, now = Time.current, built_on: nil)
    @user = user
    @project = user.project
    @now = now
    @local_now = now.in_time_zone(user.timezone.presence || "UTC")
    @built_on = built_on
  end

  def today
    local_now.to_date
  end

  # Their streak days, from Hackatime, as of now. With no project picked yet, a new Hackatime project with time on it
  # is linked for them first (Project#auto_link_hackatime_project, which DMs them about it), so its time is in the
  # sync and everything after goes on what they've really built. If Hackatime can't be reached, what we last saw
  # will do.
  def refresh!
    if project.hackatime_linked? && project.hackatime_projects.none? && available_hackatime_projects
      project.auto_link_hackatime_project(available_hackatime_projects)
    end
    StreakActivity.sync_for_user!(user)
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    nil
  ensure
    user.reload
  end

  # The Hackatime projects they could pick, or nil while Hackatime can't say.
  def available_hackatime_projects
    return @available_hackatime_projects if defined?(@available_hackatime_projects)
    @available_hackatime_projects = Hackatime.projects(user)
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    @available_hackatime_projects = nil
  end

  # Within the 15 minutes after their slot, on a day they build.
  def in_slot?
    return false if project.build_time == "weekends" && !today.on_weekend?
    hour, min = Nudge::SLOTS.fetch(project.build_time).split(":").map(&:to_i)
    slot = local_now.change(hour:, min:)
    local_now >= slot && local_now < slot + 15.minutes
  end

  def quiet?
    local_now.hour >= Nudge::QUIET_FROM || local_now.hour < Nudge::QUIET_UNTIL
  end

  # The next morning the bot may speak: today's, or tomorrow's once it's late.
  def quiet_ends_at
    morning = local_now.change(hour: Nudge::QUIET_UNTIL, min: 0)
    local_now < morning ? morning : morning + 1.day
  end

  # The bot can reach them: on Slack, not stopped, and no DM failed in the last Nudge::DM_RETRY_AFTER.
  def reachable?
    failed_at = user.slack_dm_failed_at
    user.slack_id.present? && user.slack_muted_at.nil? && (failed_at.nil? || failed_at < now - Nudge::DM_RETRY_AFTER)
  end

  # The bot DMed them something (anything: a nudge, a cheer, a reward, their project linking itself) within the last
  # MESSAGE_GAP, so nothing else goes yet.
  def just_messaged?
    user.slack_dmed_at.present? && user.slack_dmed_at > now - Nudge::MESSAGE_GAP
  end

  # Until their deadline (Project#program_dates), not quiet hours, the bot not stopped and not just heard from, under
  # the caps, and they haven't built today already. Cheers aren't counted against the caps: they're earned, and they only go once the day's
  # building is done.
  def may_nudge?
    return false unless project.program_dates.cover?(today) && reachable?
    return false if quiet? || just_messaged? || sent_today.exists?
    return false if user.nudges.delivered.where.not(kind: "cheer").where(sent_at: now - 7.days..).count >= Nudge::WEEKLY_CAP
    minutes_today < Nudge::REWARD_MINUTES
  end

  # A cheer for built_on is still owed: before their deadline, the bot not stopped, the day's still today or yesterday
  # with its 20 minutes still there, and no cheer for that day, or any today, yet.
  def cheer_due?
    return false unless built_on && project.program_dates.cover?(today) && reachable?
    return false if !(today - 1..today).cover?(built_on) || minutes_on(built_on) < Nudge::REWARD_MINUTES
    cheers = user.nudges.delivered.cheers
    !cheers.where(built_on:).or(cheers.where(sent_at: local_now.beginning_of_day..)).exists?
  end

  # Owed, and this is a moment the bot can speak: not quiet hours, nothing else just said.
  def may_cheer?
    cheer_due? && cheer_waits_until.nil?
  end

  # When a cheer owed now can go instead, if not now: once quiet hours end, or MESSAGE_GAP after whatever the bot
  # last DMed them. Nil when now's fine.
  def cheer_waits_until
    return quiet_ends_at if quiet?
    user.slack_dmed_at + Nudge::MESSAGE_GAP if just_messaged?
  end

  # The streak day a comeback DM would be for: the one before today, when they built (Growth::ACTIVE_SECONDS) on some day
  # before it but neither on it nor yet today, and it was a day they'd build (a weekend builder has no missed Fridays). Nil
  # for someone who never built: the setup nudges are for them.
  def comeback_missed_on
    today = StreakActivity.streak_date_for(now, user.timezone)
    missed = today - 1
    return unless project.build_day?(missed) && seconds_on(today) < Growth::ACTIVE_SECONDS && seconds_on(missed) < Growth::ACTIVE_SECONDS

    missed if user.streak_activities.where(activity_date: ...missed, coded_seconds: Growth::ACTIVE_SECONDS..).exists?
  end

  # Whether a comeback DM can promise a free sticker pack: they could claim it (Hack Club Auth's YSWS-eligible and not
  # banned on Hackatime, D-051) and haven't got Reward::STICKER_PACKS_MAX already.
  def stickers_to_promise?
    user.sticker_eligible? && Reward.sticker_packs_earned(user) < Reward::STICKER_PACKS_MAX
  end

  def sent_today
    user.nudges.delivered.where(sent_at: local_now.beginning_of_day..)
  end

  # Only bandit nudges use buckets.
  def bucket
    if hours.zero? then "zero_hours"
    elsif lapsed? then "lapsed"
    elsif on_pace? then "on_pace"
    else "behind"
    end
  end

  def lapsed?
    last_built_on.nil? || last_built_on < today - LAPSED_AFTER_DAYS
  end

  # Have you built at least pace_minutes for every build day before today?
  def on_pace?
    hours >= project.build_days.count { |day| day < today } * project.pace_minutes / 60.0
  end

  def hours = @hours ||= project.hours_logged
  def streak = user.current_streak
  def minutes_today = minutes_on(user.streak_today_date)
  def minutes_on(date) = seconds_on(date) / 60
  def seconds_on(date) = user.streak_activities.find_by(activity_date: date)&.coded_seconds.to_i
  def last_built_on = @last_built_on ||= user.streak_activities.where(coded_seconds: 1..).maximum(:activity_date)

  # Other participants who built today (or on the day a cheer's for), admins aside (D-032).
  def peers
    @peers ||= StreakActivity.where(activity_date: built_on || user.streak_today_date, coded_seconds: 1.., user_id: User.participants).where.not(user_id: user.id).count
  end

  # What copy can fill in. Names and titles are other people's text, so they're escaped for Slack (SlackText). Anything missing or not worth saying (a 0 streak, 1 peer) is left out, and copy that
  # needs it won't be picked.
  def vars
    @vars ||= build_vars
  end

  private
    def build_vars
      hours_needed = project.hours_needed
      hours_left = [ hours_needed - hours, 0 ].max
      sessions_left = (hours_left * 60 / project.pace_minutes).ceil
      upcoming = helpers.project_rewards(project).find { |reward| reward[:state] == "next" }
      {
        first_name: SlackText.escape(user.first_name),
        title: SlackText.escape(project.title.downcase_first),
        prize: project.prize_short,
        a_prize: project.prize_with_article,
        hours: helpers.project_hours(hours),
        hours_word: unit(hours, "hour"),
        hours_needed: helpers.project_hours(hours_needed),
        hours_left: helpers.project_hours(hours_left.round(1)),
        hours_left_word: unit(hours_left.round(1), "hour"),
        percent: [ (hours * 100 / hours_needed).round, 100 ].min,
        sessions_left: sessions_left,
        sessions_word: unit(sessions_left, "session"),
        session_percent: (project.pace_minutes * 100.0 / (hours_needed * 60)).round,
        pace: project.pace_minutes,
        build_time: project.build_time,
        finish_on: project.finish_on.strftime("%b %-d"),
        local_time: local_now.strftime("%-l%P").strip,
        days_left: (project.deadline - today).to_i,
        streak: (streak if streak.positive?),
        streak_word: (unit(streak, "day") if streak.positive?),
        streak_next: (streak + 1 if streak.positive?),
        next_reward: (upcoming[:label].downcase if upcoming && streak.positive?),
        days_to_reward: (upcoming[:days] - streak if upcoming && streak.positive?),
        reward_days_word: (unit(upcoming[:days] - streak, "day") if upcoming && streak.positive?),
        sticker_minutes: Reward::STICKERS_SECONDS / 60,
        peers: (peers if peers >= MIN_PEERS),
        days_idle: ((today - last_built_on).to_i if last_built_on && lapsed?),
        **leaderboard_vars,
        **cheer_vars
      }.compact
    end

    # Where you are on this week's board, for the overtake copy: your rank, who's just above you and how many
    # minutes would pass them, when that's one session's worth (GAP_MINUTES). Only once you have hours:
    # at zero everyone's tied, and a rank among ties means nothing. passed_by is who went past you since
    # yesterday's snapshot, if you've dropped and they're now the one above.
    def leaderboard_vars
      return {} unless project.set_up? && project.hours_logged.positive?
      place = Leaderboard.place_of(project) or return {}
      gap = place.gap_minutes
      close = gap && gap.positive? && gap <= GAP_MINUTES
      dropped = place.change&.negative?
      { rank: place.rank, above: (SlackText.escape(place.above.user.public_name) if close), gap_minutes: (gap if close), gap_word: (unit(gap, "minute") if close),
        passed_by: (SlackText.escape(place.above.user.public_name) if close && dropped), places_lost: (-place.change if dropped) }
    end

    # For a cheer: how long they built on the day it's for, and which day that is from where they are now ("today"
    # or "yesterday", so a cheer held for the morning still reads right).
    def cheer_vars
      return {} unless built_on
      { minutes: minutes_on(built_on), day: built_on == today ? "today" : "yesterday", next_day: built_on == today ? "tomorrow" : "today" }
    end

    # "hour" for exactly 1, otherwise "hours", so copy never says "1 hours".
    def unit(count, word)
      count == 1 ? word : "#{word}s"
    end

    def helpers
      ApplicationController.helpers
    end
end
