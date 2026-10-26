# Save Point itself: when it runs, and how hours turn into a prize (the rates are in Shop).
module Program
  # D-017: Save Point runs 10 days. The end is the last moment to ship. The landing page shows only the end, in your own
  # time zone.
  #
  # D-025: it starts when the site goes live. PROGRAM_STARTS_AT (ISO 8601, e.g. 2026-10-23T01:30:00Z) sets the start;
  # without it, or when it doesn't parse, the start is D-017's, DEFAULT_STARTS_AT. Read once, when the app loads.
  DEFAULT_STARTS_AT = Time.utc(2026, 10, 23, 21)

  # The start from an env value: a valid ISO 8601 time with a zone, else the default.
  def self.starts_at_from(value)
    return DEFAULT_STARTS_AT if value.blank?

    Time.iso8601(value.strip).utc
  rescue ArgumentError
    DEFAULT_STARTS_AT
  end

  STARTS_AT = starts_at_from(ENV["PROGRAM_STARTS_AT"])
  ENDS_AT = Time.utc(2026, 11, 2, 21)

  # D-078: the last third of Save Point, from about Oct 30, when effort rises as a goal gets near (Kivetz 2006). From
  # then the project page leads with the minutes left to your goal prize.
  GOAL_SALIENCE_STARTS_AT = ENDS_AT - (ENDS_AT - STARTS_AT) / 3

  # The calendar dates of the program, UTC: the start's date to the end's date. Hours are kept per date (StreakActivity).
  DATES = STARTS_AT.to_date..ENDS_AT.to_date
  # What an extension (Extension) was: this many days past the old last day. Save Point itself runs that long now, so
  # one moves nothing, and nobody can ask (Project#extension_requestable?).
  EXTENSION_DAYS = 7
  # Ship stays open this many days past the deadline, quietly: nobody's told, and the site keeps saying the deadline.
  SHIP_GRACE_DAYS = 2
  # The first hours pay more (Shop::FIRST_RATE an hour; Shop::RATE after), and the stats count who's past them.
  HOURS_PER_REWARD = 10
  # The date Hackatime is asked from (its stats take dates), D-003, D-017. Only time after STARTS_AT counts (D-055): the sync
  # clips each span at that moment (StreakActivity). This date is not the first streak day, see FIRST_STREAK_DATE.
  HACKATIME_START = STARTS_AT.to_date
  # D-055: the earliest streak day (2am to 2am, in your timezone) that can hold counted time: the one containing STARTS_AT
  # for someone at UTC-12. West of UTC it is the day before HACKATIME_START (21:14 to 02:00 EDT on Oct 22 is after a
  # 01:14 UTC launch). Spans before STARTS_AT are clipped, so earlier days are zero. Queries over hours start here.
  FIRST_STREAK_DATE = (STARTS_AT - 14.hours).utc.to_date
  # The project picker lists only projects with time on or after this day (D-013). It doesn't change which hours count.
  HACKATIME_PICK_SINCE = Date.new(2026, 10, 22)
  # Where shoutouts post (D-018): #savepoint, the same public channel as below (RewardNotifier). The bot joins it itself.
  SHOUTOUT_CHANNEL_ID = "C0CBHCHK469"
  # D-028: everyone whose Slack is linked is added to Save Point's channel (JoinSlackChannelsJob). The channel is public,
  # so the bot joins it itself when it isn't in it (SlackBot.joining).
  SLACK_CHANNEL_IDS = [ "C0CBHCHK469" ].freeze
  # D-023: we play everyone's game live on stream, Thursday 7pm Eastern (EDT, 23:00 UTC).
  PLAY_PARTY_AT = Time.find_zone("America/New_York").local(2026, 10, 30, 19)
  # The party's calendar day in Eastern time, for the day strip and the sidebar.
  PLAY_PARTY_ON = PLAY_PARTY_AT.to_date

  # Which day of Save Point it is: { number:, total: }, counted in 24-hour days from STARTS_AT to ENDS_AT (so the same
  # for everyone, whatever their time zone), the last day once it's over, and nil before the start. Days turn over at
  # STARTS_AT's time of day. The total rounds, so a leftover under 12 hours stretches the last day instead of making a
  # sliver of an extra one (a 01:30 UTC start gives 11 days, the last one 19.5 hours long).
  def self.day(now = Time.current)
    return if now < STARTS_AT

    total = [ ((ENDS_AT - STARTS_AT) / 1.day).round, 1 ].max
    { number: [ ((now - STARTS_AT) / 1.day).floor + 1, total ].min, total: total }
  end

  # The calendar day that stands for today's Save Point day, since hours are kept per date (StreakActivity), not per
  # instant. A program day runs 24 hours from STARTS_AT, so for a late start (21:00 UTC) it is mostly the next UTC date:
  # the date at the day's midpoint. Before the start, the UTC calendar day. D-015 leaves the real boundary open.
  def self.today(now = Time.current)
    day = self.day(now)
    return now.utc.to_date unless day

    (STARTS_AT + (day[:number] - 1).days + 12.hours).utc.to_date
  end

  # Whether it's the last third of the program, up to the end and after.
  def self.goal_salient?(now = Time.current)
    now >= GOAL_SALIENCE_STARTS_AT
  end

  # "Day 3 of 10", or "Starts soon" before the start.
  def self.day_label(now = Time.current)
    day = self.day(now)
    day ? "Day #{day[:number]} of #{day[:total]}" : "Starts soon"
  end
end
