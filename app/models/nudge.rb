# One message the bot sent someone on Slack, and whether they built afterwards. Every send is logged with the odds the
# bandit picked it at (propensity), so we can judge other policies against this log later.
#
# Every 15 minutes (NudgeDeliveryJob), anyone whose local time just reached the slot for when they said they'd build
# gets at most one: a fixed one if anything applies (Nudge::Fixed), otherwise whatever the bandit picks
# (Nudge::Bandit). And whenever a sync shows someone's just built their 20 minutes for the day, the bot cheers
# (Nudge::Cheer). Nothing goes within MESSAGE_GAP of anything else the bot DMed them (User#slack_dmed_at: nudges,
# cheers, rewards, a project linking itself), so its messages never land together: a nudge's slot passes, a cheer
# waits. Hourly (NudgeScoringJob), each one whose window has closed is scored on whether they built, or for a setup
# nudge, whether they did the step it asked for. A bandit or comeback nudge worked if they built at all within
# WORKED_WINDOW (a comeback DM can also promise a free sticker pack for coming back, Reward.award_comeback_stickers!).
# What it says is Nudge::Copy, the Slack message is Nudge::Message, and its links are NudgeLinksController.
class Nudge < ApplicationRecord
  # Bandit nudges and cheers are learned from. The rest always send when they apply, bar test ones
  # (bin/rails nudges:test), which are never scored or counted.
  KINDS = %w[bandit cheer setup milestone program streak_saver comeback test].freeze
  LEARNED = %w[bandit cheer].freeze

  # What keeps a streak going. Milestone, program and streak saver nudges count as working when they built this long
  # within REWARD_WINDOW of one. A cheer's window is the whole of the next streak day instead (see #window).
  REWARD_MINUTES = 20
  REWARD_WINDOW = 6.hours
  # A bandit or comeback nudge worked if they built any streak day's worth (Growth::ACTIVE_SECONDS) within this long
  # of it, like Duolingo's "lesson within 2 hours" (Yancey & Settles 2020, D-078).
  WORKED_KINDS = %w[bandit comeback].freeze
  WORKED_WINDOW = 2.hours
  # Stopping the bot's messages from a nudge counts as this many failures.
  OPT_OUT_PENALTY = -5

  DAILY_CAP = 1
  WEEKLY_CAP = 5
  # The least time between any two of the bot's DMs to someone.
  MESSAGE_GAP = 1.hour

  # Local time. Nothing sends at or after QUIET_FROM or before QUIET_UNTIL, late night builders included.
  QUIET_FROM = 22
  QUIET_UNTIL = 8

  # Local send time for each build time. Weekend builders only hear from the bot on Saturdays and Sundays.
  # TODO: a second bandit over sending at the slot vs an hour before it.
  SLOTS = { "after school" => "15:30", "evening" => "19:00", "late night" => "21:30", "weekends" => "11:00" }.freeze

  # built_on is the streak day a cheer is for, and for a comeback nudge the day they missed.
  belongs_to :user

  # The tracked links: /n/<token> goes where the button says, /n/<token>/stop stops the bot's messages.
  has_secure_token :token

  # A failed DM is tried again after this long. A hiccup on Slack's side shouldn't silence someone for the whole program.
  # Not a full 24 hours: the failure is stamped a few seconds after the slot opens, and the only run inside the slot the
  # next day happens at the same few seconds past, so `now - 24.hours` lands just before the stamp and re-races it every day.
  DM_RETRY_AFTER = 23.hours

  # The nudge for signed-in people with no project (deliver_pledge_nudges): its arm, the slot it goes at (the evening's),
  # and how long after signing up the first one waits, so it isn't the first thing they see.
  PLEDGE_ARM = "pledge_setup"
  PLEDGE_SLOT = "evening"
  PLEDGE_MIN_AGE = 3.hours

  validates :kind, inclusion: { in: KINDS }

  scope :bandit, -> { where(kind: LEARNED) }
  scope :cheers, -> { where(kind: "cheer") }
  scope :delivered, -> { where(delivered: true) }
  scope :real, -> { where.not(kind: "test") }
  scope :scored, -> { where.not(reward: nil) }
  scope :unscored, -> { delivered.where(reward: nil) }

  # Everyone whose slot it is (with a timezone, on Slack, and not muted), one at a time so one person's trouble
  # doesn't stop the rest.
  def self.deliver_due(now = Time.current)
    User.joins(:project).includes(:project).where.not(timezone: nil).where.not(slack_id: [ nil, "" ])
        .where(slack_muted_at: nil).where("slack_dm_failed_at IS NULL OR slack_dm_failed_at < ?", now - DM_RETRY_AFTER).find_each do |user|
      deliver_to(user, now)
    rescue => error
      Rails.error.report(error, context: { user_id: user.id })
    end
  end

  # Sign-ins who never pledged a project have no build time or Nudge::Context, so they get one fixed DM (arm
  # PLEDGE_ARM) at the evening slot, at least PLEDGE_MIN_AGE after they signed up, and again after
  # Nudge::Context::SETUP_EVERY while they still haven't. Admins and anyone muted or recently unreachable are left out,
  # as in deliver_due. The arm isn't "pledge", which is the bandit's arm for people who have.
  def self.deliver_pledge_nudges(now = Time.current)
    pledge_candidates(now).find_each do |user|
      deliver_pledge_nudge(user, now)
    rescue => error
      Rails.error.report(error, context: { user_id: user.id })
    end
  end

  # Everyone with no project who the bot can reach and who isn't an admin, signed up long enough ago.
  def self.pledge_candidates(now = Time.current)
    User.participants.where.missing(:project).where.not(timezone: nil).where.not(slack_id: [ nil, "" ])
        .where(slack_muted_at: nil).where("slack_dm_failed_at IS NULL OR slack_dm_failed_at < ?", now - DM_RETRY_AFTER)
        .where(created_at: ..now - PLEDGE_MIN_AGE)
  end

  # Their pledge nudge, if it's their slot, the program's running and the bot hasn't just said something.
  def self.deliver_pledge_nudge(user, now = Time.current)
    local_now = now.in_time_zone(user.time_zone)
    return unless Program::DATES.cover?(local_now.to_date)

    hour, min = SLOTS.fetch(PLEDGE_SLOT).split(":").map(&:to_i)
    slot = local_now.change(hour:, min:)
    return unless local_now >= slot && local_now < slot + 15.minutes && user.created_at <= slot - PLEDGE_MIN_AGE
    return if user.slack_dmed_at.present? && user.slack_dmed_at > now - MESSAGE_GAP
    return if user.nudges.delivered.where(kind: "setup", arm: PLEDGE_ARM, sent_at: now - Nudge::Context::SETUP_EVERY..).exists?

    nudge = user.nudges.new(kind: "setup", arm: PLEDGE_ARM, propensity: 1.0)
    nudge.deliver!({})
    nudge
  end

  # Their nudge, if it's their slot and they should get one. Their hours are brought up to date first.
  def self.deliver_to(user, now = Time.current)
    context = Nudge::Context.new(user, now)
    return unless context.in_slot?

    context.refresh!
    return unless context.may_nudge?

    nudge = Nudge::Fixed.for(context) || Nudge::Bandit.nudge_for(context)
    nudge&.deliver!(context.vars)
    nudge
  end

  def self.score_due(now = Time.current)
    unscored.real.where(sent_at: ..now - WORKED_WINDOW).find_each do |nudge|
      next if nudge.window_closes_at > now
      nudge.score!
    rescue Hackatime::Unavailable
      # Tried again next hour.
    end
  end

  def cheer? = kind == "cheer"
  def setup? = kind == "setup"
  def worked_quickly? = WORKED_KINDS.include?(kind)

  # When building counts as this nudge working: the WORKED_WINDOW after a bandit or comeback nudge, the six hours after
  # the rest, or for a cheer, the whole of the next streak day (2am to 2am in their timezone), since a cheer's job is
  # getting them to come back.
  def window
    return sent_at..sent_at + (worked_quickly? ? WORKED_WINDOW : REWARD_WINDOW) unless cheer?

    next_day = built_on + 1
    from = ActiveSupport::TimeZone[user.timezone.presence || "UTC"].local(next_day.year, next_day.month, next_day.day, 2)
    from..from + 1.day
  end

  def window_closes_at
    window.end
  end

  # 1 if they built in the window (Growth::ACTIVE_SECONDS for a bandit or comeback nudge, REWARD_MINUTES for the rest, or
  # for a setup nudge, did the step it asked for), 0 if not, OPT_OUT_PENALTY if this nudge made them stop the bot's
  # messages. Ones scored before the 2-hour rule keep the reward they got under the old one (20 minutes in 6 hours).
  def score!
    seconds = opted_out_at ? 0 : built_seconds
    reward =
      if opted_out_at then OPT_OUT_PENALTY
      elsif setup? then step_done? ? 1 : 0
      elsif seconds >= (worked_quickly? ? Growth::ACTIVE_SECONDS : REWARD_MINUTES * 60) then 1
      else 0
      end
    update!(reward:, rewarded_at: Time.current)
  end

  # Whether the step a setup nudge asked for is done now. Nothing records when it was done, so a setup nudge is
  # scored on the state when its window closes: a step done after that goes to the next one for it, if any. Getting
  # time onto Hackatime (plugin) is done once Hackatime has a project with time, picked or not.
  def step_done?
    project = user.project
    case arm
    when PLEDGE_ARM then project.present?
    when "hackatime" then user.hackatime_linked?
    when "plugin" then project.present? && (project.hackatime_projects.any? || hackatime_has_time?)
    when "hackatime_project" then project.present? && project.hackatime_projects.any?
    when "repo" then project.present? && (project.repo_url.present? || project.repo_later?)
    else false
    end
  end

  # Whether Hackatime has any time from them since Save Point started. Unavailable is left to raise, so the scoring
  # tries again next hour.
  def hackatime_has_time?
    Hackatime.projects(user).any? { |each| each.seconds.positive? }
  rescue Hackatime::NotLinked, Hackatime::Expired
    false
  end

  # Time on their linked Hackatime projects in the window. Nothing linked, or Hackatime not linked any more, is none.
  def built_seconds = seconds_between(window)

  # Time on their linked Hackatime projects in the Reward::COMEBACK_WINDOW after a comeback DM, for its sticker pack.
  def coded_after = seconds_between(sent_at..sent_at + Reward::COMEBACK_WINDOW)

  def seconds_between(times)
    project = user.project
    return 0 unless project&.tracking?

    Hackatime.seconds_between(user, project.hackatime_projects, times)
  rescue Hackatime::NotLinked, Hackatime::Expired
    0
  end

  # A DM from the bot. If the bot can't DM them, why is kept (Slack's error code) and it's tried again after
  # DM_RETRY_AFTER. A DM that goes through clears that.
  def deliver!(vars)
    self.variant, self.text = Nudge::Copy.render(self, vars)
    save! # for the token in its links
    error = nil
    message = SlackBot.dm(user.slack_id, text:, blocks: Nudge::Message.new(self).blocks, on_error: ->(code) { error = code })
    if message.nil? && Rails.configuration.x.slack_configured
      user.update!(slack_dm_failed_at: Time.current, slack_dm_error: error.to_s.truncate(100))
    elsif message.present? && (user.slack_dm_failed_at || user.slack_dm_error)
      user.update!(slack_dm_failed_at: nil, slack_dm_error: nil)
    end
    update!(delivered: message.present?, slack_channel: message&.channel, slack_ts: message&.ts, sent_at: Time.current)
    return unless delivered
    user.slack_dmed!(sent_at)
  end

  def link_url = "#{Rails.configuration.x.app_url}/n/#{token}"
  def stop_url = "#{Rails.configuration.x.app_url}/n/#{token}/stop"

  # Where the button goes, past the tracked link.
  def destination_url
    case Nudge::Copy.link_for(arm).last
    when :leaderboard then "#{Rails.configuration.x.app_url}/leaderboard"
    when :hackatime_site then ApplicationController.helpers.hackatime_url
    when :onboarding then "#{Rails.configuration.x.app_url}/start"
    else "#{Rails.configuration.x.app_url}/project" # Linking Hackatime, picking your project and adding a repo are on the project page too.
    end
  end

  # Someone clicked the button. Counted every time, but the first click is the one that matters.
  def clicked!
    self.class.where(id:).update_all([ "clicks = clicks + 1, clicked_at = COALESCE(clicked_at, ?)", Time.current ])
    reload
  end
end
