# Pretend Hackatime, for development only (Hackatime.fake): a handful of plausible projects and building time for
# anyone, so the project picker, the project page and the hours work without the real API. Fake people (bin/rails
# dev:fake) get the spans their seeded days say; anyone else, Armand included, gets a steady made-up pattern.
module Hackatime::Fake
  # Projects any account has "logged time on", whatever else they've linked: name, seconds since Hackatime started
  # counting, and whether it has time since the program started (the rest are old projects, with earlier time only).
  POOL = [
    [ "moonlit-platformer", 23_040, true ],
    [ "pixel-farm", 8_280, true ],
    [ "godot-shooter-prototype", 2_880, true ],
    [ "gamejam-entry-2026", 5_400, false ],
    [ "dotfiles", 4_020, false ]
  ].freeze

  # Spans on days this many minutes apart look steady but not robotic.
  SPAN_START_HOUR_UTC = 12

  # /dev can pin someone's hours to a number (Dev::MyProject): the fake time is then exactly that many hours, laid out from
  # the first Hackatime day at up to PINNED_DAY_SECONDS a day, so a sync never undoes it. Kept in a file so a restart
  # doesn't forget it; { user id => hours }.
  mattr_accessor :pin_file, default: Rails.root.join("tmp/dev_pinned_hours.json")
  PINNED_DAY_SECONDS = 18 * 3600

  def self.pinned_hours(user)
    hours = JSON.parse(pin_file.read).fetch(user.id.to_s, nil) if pin_file.exist?
    hours&.to_r
  rescue JSON::ParserError
    nil
  end

  # Pin the hours, or with nil unpin them (back to the usual made-up pattern).
  def self.pin_hours!(user, hours)
    pins = pin_file.exist? ? (JSON.parse(pin_file.read) rescue {}) : {}
    hours.nil? ? pins.delete(user.id.to_s) : pins[user.id.to_s] = hours.to_f
    pin_file.dirname.mkpath
    pin_file.write(JSON.generate(pins))
  end

  # The seconds each day holds when `hours` are pinned: first day first, a day at most PINNED_DAY_SECONDS.
  def self.pinned_days(hours)
    left = (hours * 3600).round
    days = {}
    Program::DATES.each do |date|
      break if left <= 0

      days[date] = [ left, PINNED_DAY_SECONDS ].min
      left -= days[date]
    end
    days
  end

  def self.user_id(token)
    "fake-#{Digest::SHA256.hexdigest(token.to_s).first(8)}"
  end

  def self.projects(user)
    linked = user.project&.hackatime_projects.to_a
    # A linked project that's one of the pool keeps its own time (so two never read the same); a name Armand typed gets the
    # steady made-up time, shared out.
    pool = POOL.to_h { |name, seconds, _| [ name, seconds ] }
    others = linked.reject { |name| pool.key?(name) }
    own = linked.map { |name| [ name, pool[name] || own_seconds(user) / [ others.size, 1 ].max, true ] }
    (own + POOL.reject { |name, *| linked.include?(name) }).map { |name, seconds, _| Hackatime::Project.new(name, seconds) }
  end

  # No repo links, so auto-link never skips a fake project.
  def self.repo_urls(_user) = {}

  # D-089: every project, the ones with time that counts first and the old ones with earlier time only.
  def self.pickable_projects(user)
    linked = user.project&.hackatime_projects.to_a
    pool = projects(user).index_by(&:name)
    recent = POOL.select { |_, _, recent| recent }.map(&:first) | linked
    pool.values.map do |project|
      recent.include?(project.name) ? Hackatime::Project.new(project.name, project.seconds, 7_200) : Hackatime::Project.new(project.name, 0, project.seconds)
    end.sort_by { |pick| pick.seconds.positive? ? [ 0, -pick.seconds ] : [ 1, -pick.earlier_seconds ] }
  end

  # No "ai coding" or art time, so a fake ship's review applies no cut.
  def self.category_seconds(_user, _category) = 0

  # /dev can plant a span at an exact moment (the sticker promise's first-hour window, D-051): the made-up day pattern
  # always starts at noon, so it can never land inside an hour that just started. Kept in a file like the pinned
  # hours; { user id => [ { "start" => epoch seconds, "duration" => seconds }, ... ] }.
  mattr_accessor :planted_file, default: Rails.root.join("tmp/dev_planted_spans.json")

  def self.planted_spans(user)
    (JSON.parse(planted_file.read) rescue {}).fetch(user.id.to_s, []) if planted_file.exist?
  end

  def self.plant_span!(user, start:, duration:)
    plans = planted_file.exist? ? (JSON.parse(planted_file.read) rescue {}) : {}
    (plans[user.id.to_s] ||= []) << { "start" => start.to_f, "duration" => duration.to_i }
    planted_file.dirname.mkpath
    planted_file.write(JSON.generate(plans))
  end

  # /dev can set the trust level Hackatime would report for someone (D-051): "red" is a ban. Kept in a file like the
  # pinned hours; { user id => level }. Everyone is "blue" until it says otherwise.
  mattr_accessor :trust_file, default: Rails.root.join("tmp/dev_trust_levels.json")
  DEFAULT_TRUST_LEVEL = "blue"

  def self.trust_level(user)
    levels = trust_file.exist? ? (JSON.parse(trust_file.read) rescue {}) : {}
    levels.fetch(user.id.to_s, DEFAULT_TRUST_LEVEL)
  end

  def self.set_trust_level!(user, level)
    levels = trust_file.exist? ? (JSON.parse(trust_file.read) rescue {}) : {}
    level.nil? ? levels.delete(user.id.to_s) : levels[user.id.to_s] = level
    trust_file.dirname.mkpath
    trust_file.write(JSON.generate(levels))
  end

  # Hackatime's heartbeat spans between two dates (end exclusive) on these projects.
  def self.spans(user, project_names, start_date:, end_date:)
    return [] if (project_names.to_a & projects(user).map(&:name)).empty?

    seconds = day_seconds(user, start_date, end_date)
    pinned = pinned_hours(user)
    zone = Time.find_zone(user.timezone.presence) || Time.find_zone("UTC")
    days = seconds.filter_map do |date, duration|
      next unless duration.positive?

      # A pinned day is centred on noon where they are, so no span crosses the 2am the streak day turns over at.
      start = pinned ? zone.local(date.year, date.month, date.day, 12) - duration / 2 : Time.utc(date.year, date.month, date.day, SPAN_START_HOUR_UTC)
      { "start_time" => start.to_f, "end_time" => (start + duration).to_f, "duration" => duration }
    end
    planted = planted_spans(user).to_a.filter_map do |span|
      date = Time.zone.at(span["start"]).utc.to_date
      next unless date >= start_date && date < end_date

      { "start_time" => span["start"], "end_time" => span["start"] + span["duration"], "duration" => span["duration"] }
    end
    days + planted
  end

  def self.fake_person?(user) = user.hca_id.to_s.start_with?("ident!fake-")

  def self.own_seconds(user)
    user.streak_activities.sum(:coded_seconds).nonzero? || 11_160
  end

  # Fake people: their seeded days. Anyone else: some days off, otherwise 15 to 105 minutes, the same every time.
  def self.day_seconds(user, start_date, end_date)
    days = (start_date...end_date).select { |date| date >= Program::HACKATIME_START && date <= Program.today }
    if (pinned = pinned_hours(user))
      plan = pinned_days(pinned)
      return days.to_h { |date| [ date, plan.fetch(date, 0) ] }
    end
    if fake_person?(user)
      rows = user.streak_activities.where(activity_date: days).pluck(:activity_date, :coded_seconds).to_h
      return days.to_h { |date| [ date, rows.fetch(date, 0) ] }
    end

    days.to_h do |date|
      roll = Digest::SHA256.hexdigest("#{user.hackatime_uid}/#{date}").first(6).to_i(16) % 100
      [ date, roll < 20 ? 0 : (15 + roll % 91) * 60 ]
    end
  end
  private_class_method :own_seconds, :day_seconds
end
