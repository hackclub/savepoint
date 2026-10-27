require "net/http"

# Hackatime, where hours come from. Once you've linked it (OAuth, see HackatimeLinksController), your token gets an
# API key that reads your own stats, private or not: the projects you've logged time on since
# Program::HACKATIME_START (for hours and nudges) and all your projects ever (to pick from, D-089; both cached for a while, and Refresh on the project page asks again) and the
# spans of time you built on them (for your streak days, which every number of hours comes from: StreakActivity).
module Hackatime
  # `seconds` is the time that counts (since the start asked for); `earlier_seconds` is the time before it, which never
  # counts (D-089). Only the picker's list carries earlier time.
  Project = Data.define(:name, :seconds, :earlier_seconds) do
    def initialize(name:, seconds:, earlier_seconds: 0) = super

    def hours = (seconds / 3600.0).round(1)
    def earlier_hours = (earlier_seconds / 3600.0).round(1)
  end

  # D-089: the picker lists every project you have, so its stats go back to before Hackatime existed.
  ALL_TIME_FROM = Date.new(2020, 1, 1)

  # You haven't linked Hackatime, or it stopped accepting the token you linked with (link it again).
  class NotLinked < StandardError; end
  class Expired < StandardError; end
  # Hackatime couldn't be reached, or answered something we can't use.
  class Unavailable < StandardError; end

  # Tests set these instead of asking the real Hackatime: { token => Hackatime user ID },
  # { Hackatime user ID => [ Project, ... ] } and { Hackatime user ID => [ span, ... ] }.
  # Tests may also set { Hackatime user ID => [ Project, ... ] } for every project you ever had (the picker's list, D-089);
  # when it isn't set, the stubbed projects are all there is, with no earlier time.
  # Tests may set { Hackatime user ID => { category => seconds } } for category_seconds (:unavailable acts out a failure).
  # Tests may set { Hackatime user ID => { project name => repo link } } for repo_urls (:unavailable acts out a failure;
  # a user it doesn't name has no repo links).
  # Tests may set { Hackatime user ID => "red" } for the trust level a stats answer carries (:unavailable acts out a failure;
  # a user it doesn't name has no trust level in the answer).
  mattr_accessor :stubbed_users, :stubbed_projects, :stubbed_spans, :stubbed_all_projects, :stubbed_category_seconds,
                 :stubbed_trust_levels, :stubbed_repo_urls

  # Development only: made-up projects and hours for anyone (Hackatime::Fake), so nothing asks the real API. On by
  # default in development; FAKE_HACKATIME=0 turns it off. Never on in production, and off in test unless a test sets it.
  mattr_accessor :fake, default: Rails.env.development? && ENV.fetch("FAKE_HACKATIME", "1") != "0"

  # Who a token belongs to on Hackatime, or nil.
  def self.user_id(token)
    return Fake.user_id(token) if fake
    return stubbed_users&.[](token) if stubbed_users

    response = get("/api/v1/authenticated/me", bearer: token)
    JSON.parse(response.body)["id"]&.to_s if response.is_a?(Net::HTTPSuccess)
  rescue Unavailable, JSON::ParserError
    nil
  end

  def self.projects(user, refresh: false)
    projects_from(user, Program::HACKATIME_START, refresh:)
  end

  # Your projects with the time on each since a day (Program::HACKATIME_START for every number of hours). Cached.
  def self.projects_from(user, date, refresh: false)
    raise NotLinked unless user.hackatime_linked?
    return Fake.projects(user) if fake
    return stubbed_projects.fetch(user.hackatime_uid) { raise Expired } if stubbed_projects

    fetch_projects(user, "hackatime/projects", date, refresh:)
  end

  # Every project you ever logged time on, with its whole time (D-089). Cached.
  def self.all_projects(user, refresh: false)
    return stubbed_all_projects.fetch(user.hackatime_uid) { raise Expired } if stubbed_all_projects&.key?(user.hackatime_uid)
    return stubbed_projects.fetch(user.hackatime_uid) { raise Expired } if stubbed_projects

    fetch_projects(user, "hackatime/all-projects", ALL_TIME_FROM, refresh:)
  end

  def self.fetch_projects(user, cache_name, date, refresh:)
    path = projects_path(date)
    Rails.cache.fetch([ cache_name, user.hackatime_uid, date ], expires_in: 5.minutes, force: refresh) do
      response = stats(user, path)
      if response.is_a?(Net::HTTPUnauthorized) # a stale API key: get a fresh one and try once more
        Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
        response = stats(user, path)
      end
      raise Expired if response.is_a?(Net::HTTPUnauthorized)
      raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      remember_trust_level(user, body)
      body.dig("data", "projects").to_a.map { |project| Project.new(project["name"], project["total_seconds"].to_i) }
    end
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end
  private_class_method :fetch_projects

  # The repo each of your projects is linked to on Hackatime, { name => repo link }, for the projects that have one (D-064:
  # auto-link skips a project whose repo isn't the Save Point project's). Hackatime sets the link itself when a project's
  # name matches one of your public GitHub repos, and you can set it by hand. One request for every project since
  # Program::HACKATIME_START, from `projects/details`: { "projects" => [ { "name" =>, "repo_url" => (nil without one), ... } ] }.
  # Cached like `projects`. Raises Unavailable and Expired like it does.
  def self.repo_urls(user, refresh: false)
    raise NotLinked unless user.hackatime_linked?
    return Fake.repo_urls(user) if fake
    if stubbed_repo_urls
      links = stubbed_repo_urls.fetch(user.hackatime_uid, {})
      raise Unavailable, "stubbed failure" if links == :unavailable
      return links
    end

    Rails.cache.fetch([ "hackatime/repo-urls", user.hackatime_uid, Program::HACKATIME_START ], expires_in: 5.minutes, force: refresh) do
      response = stats(user, repo_urls_path)
      if response.is_a?(Net::HTTPUnauthorized) # a stale API key: get a fresh one and try once more
        Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
        response = stats(user, repo_urls_path)
      end
      raise Expired if response.is_a?(Net::HTTPUnauthorized)
      raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      parse_repo_urls(response.body)
    end
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end

  # Each project with a repo link in a `projects/details` answer, { name => repo link }.
  def self.parse_repo_urls(body)
    JSON.parse(body)["projects"].to_a.filter_map { |project| [ project["name"], project["repo_url"] ] if project["repo_url"].present? }.to_h
  end

  def self.repo_urls_path
    "/api/v1/users/my/projects/details?#{{ start_date: Program::HACKATIME_START.iso8601 }.to_query}"
  end

  # The projects to pick from (D-089): every project you have on Hackatime, with its time since `since` (the moment your
  # hours start, D-065) and its earlier time, which never counts. Projects with time that counts come first, in
  # Hackatime's order (most time first), then the older ones, most earlier time first. Two requests, both cached: your whole history, and the time
  # since your start (the same request as `projects` when you started with Save Point, so then it costs nothing extra).
  # A project with heartbeats but no seconds isn't listed (that's how the empty scan folders stay out).
  def self.pickable_projects(user, refresh: false, since: default_start(user))
    raise NotLinked unless user.hackatime_linked?
    return Fake.pickable_projects(user) if fake

    counted = projects_from(user, [ since.to_date, Program::HACKATIME_START ].max, refresh:).index_by(&:name)
    everything = all_projects(user, refresh:)
    picks = everything.filter_map do |project|
      seconds = [ counted[project.name]&.seconds.to_i, project.seconds ].min
      Project.new(project.name, seconds, project.seconds - seconds) if project.seconds.positive?
    end
    active, older = picks.partition { |pick| pick.seconds.positive? }
    active + older.sort_by { |pick| -pick.earlier_seconds }
  end

  # When a person's hours start before a project exists to say (onboarding): the later of the launch and their sign-up.
  def self.default_start(user)
    [ Program::STARTS_AT, user.created_at ].compact.max
  end

  # When you were building on these projects between two dates (end exclusive), as Hackatime's heartbeat spans:
  # { "start_time" =>, "end_time" =>, "duration" => } with times in epoch seconds. For streaks.
  def self.heartbeat_spans(user, project_names, start_date:, end_date:)
    raise NotLinked unless user.hackatime_linked?
    return Fake.spans(user, project_names, start_date:, end_date:) if fake
    return stubbed_spans.fetch(user.hackatime_uid, []) if stubbed_spans

    path = spans_path(project_names, start_date:, end_date:)
    response = get(path, bearer: api_key(user))
    if response.is_a?(Net::HTTPUnauthorized) # a stale API key: get a fresh one and try once more
      Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
      response = get(path, bearer: api_key(user))
    end
    raise Expired if response.is_a?(Net::HTTPUnauthorized)
    raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)["spans"].to_a
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end

  # How many seconds you built on these projects between two times, from the spans of the days around them. For
  # telling whether one of the bot's nudges worked (Nudge#score!).
  def self.seconds_between(user, project_names, times)
    spans = heartbeat_spans(user, project_names, start_date: times.begin.utc.to_date - 1, end_date: times.end.utc.to_date + 2)
    spans.sum do |span|
      overlap = [ span["end_time"].to_f, times.end.to_f ].min - [ span["start_time"].to_f, times.begin.to_f ].max
      overlap.positive? ? overlap : 0
    end.round
  end

  # Seconds on each of these projects between two times, { name => seconds }, one request each. D-063: the review sets
  # these beside the total, so a project that belongs to another game shows. Spans before Program::STARTS_AT never count
  # (D-055), so the start is clipped to it. Per-project figures can overlap in time, so they may sum to more than the
  # total, which counts each moment once.
  def self.project_seconds(user, project_names, times)
    from = [ times.begin, Program::STARTS_AT ].max
    project_names.index_with { |name| from < times.end ? seconds_between(user, [ name ], from..times.end) : 0 }
  end

  # Seconds Hackatime puts in one category ("ai coding", "designing") on these projects from `from` to just before
  # `to`, for the handbook's limits on review (D-030). Playground asks the same way: filter_by_category with
  # total_seconds=true, which sums by another path than the projects feature, so only this figure is taken from it.
  # nil when a project's name has a comma: filter_by_project splits on commas, so Hackatime can't be asked for it.
  def self.category_seconds(user, project_names, category, from:, to:)
    raise NotLinked unless user.hackatime_linked?

    names = Array(project_names).map(&:to_s).compact_blank
    return 0 if names.empty?
    return if names.any? { |name| name.include?(",") }
    return Fake.category_seconds(user, category) if fake
    if stubbed_category_seconds
      seconds = stubbed_category_seconds.fetch(user.hackatime_uid, {})[category]
      seconds = seconds.call(from, to) if seconds.respond_to?(:call)
      raise Unavailable, "stubbed failure" if seconds == :unavailable
      return seconds.to_i
    end

    path = category_path(names, category, from:, to:)
    response = get(path, bearer: api_key(user))
    if response.is_a?(Net::HTTPUnauthorized) # a stale API key: get a fresh one and try once more
      Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
      response = get(path, bearer: api_key(user))
    end
    raise Expired if response.is_a?(Net::HTTPUnauthorized)
    raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    (body["total_seconds"] || body.dig("data", "total_seconds")).to_i
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end

  # D-087: seconds Hackatime files under "coding" on these projects from `from` to just before `to`, for the DAU. Hackatime's
  # spans carry no category and can't be filtered by one, so this asks its stats for the window instead (one request).
  # nil when it can't say (a project name with a comma, Hackatime down, a made-up Hackatime): the caller counts all the time.
  # Tests that stub spans only get nil; stubbed_category_seconds["coding"] may be a proc of (from, to).
  def self.coding_seconds(user, project_names, from:, to:)
    return if fake || (stubbed_spans && !stubbed_category_seconds)

    category_seconds(user, project_names, "coding", from:, to:)
  rescue Unavailable
    nil
  end

  def self.category_path(project_names, category, from:, to:)
    query = { start_date: from.iso8601, end_date: to.iso8601, filter_by_project: project_names.join(","),
              filter_by_category: category, total_seconds: true }
    "/api/v1/users/my/stats?#{query.to_query}"
  end

  # After linking (again), so nothing cached from before sticks around.
  def self.forget(user)
    Rails.cache.delete([ "hackatime/all-projects", user.hackatime_uid, ALL_TIME_FROM ])
    (Program::HACKATIME_START..Program::DATES.end).each { |date| Rails.cache.delete([ "hackatime/projects", user.hackatime_uid, date ]) }
    Rails.cache.delete([ "hackatime/repo-urls", user.hackatime_uid, Program::HACKATIME_START ])
    Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
  end

  # Your projects, with only the time since Hackatime time started counting (so projects you haven't touched since
  # then aren't listed).
  def self.stats_path = projects_path(Program::HACKATIME_START)

  def self.projects_path(date)
    "/api/v1/users/my/stats?#{{ features: "projects", start_date: date.iso8601 }.to_query}"
  end

  # Spans on these projects between two dates. Each project goes as its own `project[]`, which Hackatime matches
  # whole: its `filter_by_project` splits on commas, so a project called "Game 26, Snake, GS" would match nothing.
  def self.spans_path(project_names, start_date:, end_date:)
    "/api/v1/users/my/heartbeats/spans?#{{ start_date: start_date.iso8601, end_date: end_date.iso8601, project: project_names }.to_query}"
  end

  # Hackatime's trust level for them ("blue", "green", "yellow", "red"), asked afresh with one small stats request, and
  # stored on the user (User#hackatime_banned?, D-051). Raises when Hackatime can't say; a stats answer without the
  # field leaves what was stored. The stickers ask this right before awarding, since a ban must stop them.
  def self.refresh_trust_level!(user)
    raise NotLinked unless user.hackatime_linked?
    if fake
      user.update_column(:hackatime_trust_level, Fake.trust_level(user))
      return user.hackatime_trust_level
    end
    if stubbed_trust_levels
      level = stubbed_trust_levels[user.hackatime_uid]
      raise Unavailable, "stubbed failure" if level == :unavailable
      user.update_column(:hackatime_trust_level, level) if level
      return user.hackatime_trust_level
    end

    path = "/api/v1/users/my/stats?#{{ start_date: Program::HACKATIME_START.iso8601 }.to_query}"
    response = stats(user, path)
    if response.is_a?(Net::HTTPUnauthorized)
      Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
      response = stats(user, path)
    end
    raise Expired if response.is_a?(Net::HTTPUnauthorized)
    raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    remember_trust_level(user, JSON.parse(response.body))
    user.hackatime_trust_level
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end

  # Store the trust level a stats answer carries (`trust_factor.trust_level`), only when it has one. No callbacks or
  # validations: this runs in the middle of reads.
  def self.remember_trust_level(user, body)
    level = body.dig("trust_factor", "trust_level") || body.dig("data", "trust_factor", "trust_level")
    user.update_column(:hackatime_trust_level, level.to_s) if level.present? && user.persisted?
  end

  def self.stats(user, path = stats_path)
    get(path, bearer: api_key(user))
  end

  # The OAuth token reads who you are and gets an API key; the API key reads your stats.
  def self.api_key(user)
    Rails.cache.fetch([ "hackatime/api_key", user.hackatime_uid ], expires_in: 1.week) do
      response = get("/api/v1/authenticated/api_keys", bearer: user.hackatime_access_token)
      raise Expired if response.is_a?(Net::HTTPUnauthorized)
      raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("token")
    end
  end

  def self.get(path, bearer:)
    uri = URI("#{Rails.configuration.x.hackatime_url}#{path}")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, "Authorization" => "Bearer #{bearer}")
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Unavailable, error.message
  end
  private_class_method :stats, :api_key, :get, :remember_trust_level
end
