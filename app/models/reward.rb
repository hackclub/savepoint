# What you earn for keeping a streak or logging hours. A row means it's been earned, once. Earning one tells whoever
# earned it on Slack (RewardNotifier). Older rows may belong to a pair (the retired buddy perks); nothing awards
# those now.
class Reward < ApplicationRecord
  # Days in a row of 20 minutes.
  STREAK = [
    { key: "gold_star", days: 3, label: "Gold star", about: "A gold star on your sheet." },
    { key: "streak_shoutout", days: 5, label: "Shoutout in Slack", about: "We post your game in the channel." }
  ].freeze

  # Hours logged on your linked Hackatime projects since the program started. None are awarded now (D-018): the
  # prize your hours pay for (Shop) is claimed by shipping, not awarded here.
  HOURS = [].freeze

  # Keys of rows from before D-018 (the flame, the skip day, the 5-hour shoutout). They stay readable; nothing earns them.
  RETIRED_KEYS = %w[flame skip_day hours_shoutout].freeze

  # Free Hack Club stickers for working on your game in your first hour (D-051). Not a streak or hours reward, so it is
  # in neither list: award_stickers! earns it, and claiming it is an Order for the zero-hour "stickers" prize.
  STICKERS = { key: "stickers", label: "Hack Club stickers", about: "Free stickers for building in your first hour." }.freeze

  # Only accounts made on or after this can earn the stickers: nobody gets them retroactively.
  # The env var is for development (walking the flow with a fake account made today); production takes the default.
  STICKERS_SINCE = ENV["STICKERS_SINCE"].present? ? Time.zone.parse(ENV["STICKERS_SINCE"]).utc : Time.utc(2026, 10, 25)
  # The window after signing up in which the time counts, and how much of it earns them.
  STICKERS_WINDOW = 1.hour
  STICKERS_SECONDS = 5 * 60
  # A sync still looks this long after signup, so time logged near the end of the hour is seen once it has synced.
  STICKERS_CHECK_UNTIL = 2.hours

  KEYS = (STREAK + HOURS + [ STICKERS ]).map { |reward| reward[:key] }.freeze

  belongs_to :user, optional: true
  belongs_to :pair, optional: true

  validates :key, inclusion: { in: KEYS }, on: :create
  validate :belongs_to_one

  # A shoutout should feel like its own moment, so the ones posted in the channel go out at least this far apart: each
  # takes the slot after the last one's, or now if that's passed.
  ANNOUNCE_GAP = 10.minutes

  before_create :take_announce_slot, if: -> { RewardNotifier.posted?(key) }
  after_create_commit -> { RewardNotifier.earned(self) }

  def self.definition(key) = (STREAK + HOURS + [ STICKERS ]).find { |reward| reward[:key] == key }

  # Every streak reward your streak has reached.
  def self.award_streak!(user)
    STREAK.each { |reward| earn(user:, key: reward[:key]) if user.current_streak >= reward[:days] }
  end

  # Every hours reward your logged hours have reached. Nothing without Hackatime linked and projects picked, since
  # hours only count from there.
  def self.award_hours!(user)
    return unless user.project&.tracking?
    hours = user.hours_in(Program::FIRST_STREAK_DATE..)
    HOURS.each { |reward| earn(user:, key: reward[:key]) if hours >= reward[:hours] }
  end

  # The stickers, if they logged STICKERS_SECONDS on the Hackatime projects linked to their game inside the hour after
  # they signed up. Time before signup never counts: the spans are clipped to the window (Hackatime.seconds_between).
  # Needs a YSWS-eligible account that Hackatime hasn't banned (D-051). Skips accounts made before STICKERS_SINCE, ones past STICKERS_CHECK_UNTIL, and ones that have them, so most syncs
  # cost no request.
  def self.award_stickers!(user)
    return unless user.created_at && user.created_at >= STICKERS_SINCE && user.created_at > STICKERS_CHECK_UNTIL.ago
    return unless user.project&.tracking?
    return if user.earned?("stickers")

    return unless user.ysws_eligible?

    window = user.created_at..(user.created_at + STICKERS_WINDOW)
    seconds = Hackatime.seconds_between(user, user.project.hackatime_projects, window)
    return unless seconds >= STICKERS_SECONDS

    # A fresh answer matters here: a ban must stop them. If Hackatime can't say, the next sync asks again.
    Hackatime.refresh_trust_level!(user)
    earn(user:, key: "stickers") if user.sticker_eligible?
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    # Looked at again on the next sync.
  end

  def self.earn(**attributes)
    find_or_create_by!(**attributes)
  rescue ActiveRecord::RecordNotUnique
    # Earned at the same moment somewhere else.
  end
  private_class_method :earn

  def definition = self.class.definition(key)

  # Who it's for.
  def users = pair ? pair.projects.map(&:user) : [ user ]

  private
    def take_announce_slot
      last = self.class.where.not(announce_at: nil).maximum(:announce_at)
      self.announce_at = [ Time.current, last && last + ANNOUNCE_GAP ].compact.max
    end

    def belongs_to_one
      errors.add(:base, "belongs to a user or a pair") unless user.nil? ^ pair.nil?
    end
end
