# D-126: the counted Hackatime time behind each commit on the review page: for each commit in the window (the project's hours start,
# D-065, to the moment of the ship), the time on the ship's Hackatime projects since the commit before it, so time with little
# code behind it stands out. A commit before the window reads "before counting", one after the ship "after ship", and the time
# after the last commit up to the ship (`tail_seconds`) has no commit behind it yet.
#
# The spans are asked of Hackatime once for the whole window and cut at the commit times here, so a span that crosses a commit
# is split. GitHub lists the newest commits first and stops at Ship::Commits::LIMIT: when it did (`more`), the earliest commit
# listed has earlier commits that aren't, so its figure is unknown (nil) rather than all the time before it.
# Never raises: when Hackatime or GitHub can't say, `for` is nil and the list shows without times.
class Ship::CommitTimes
  # seconds: nil when unknown. label: nil, :before_counting or :after_ship.
  Row = Data.define(:commit, :seconds, :label)

  # D-127: the review page draws the commits as a timeline, each block as tall as its counted time. The blocks together aim
  # at TIMELINE_PX (so a 5 to 20 hour ship fits on a screen or two). A block is never under MIN_PX (one line: time, sha, message).
  # Past MAX_PX the extra height grows at a fifth of the rate, so a huge block doesn't swallow the page but stays the tallest
  # (the curve rises with time and never flattens, so two long commits don't tie).
  TIMELINE_PX = 750
  MIN_PX = 44
  MAX_PX = 320
  TALL_PX = 96 # from here a block has room to wrap the message and show the author and date

  attr_reader :rows, :tail_seconds

  # Height in px of a block of `seconds` (nil, for an unknown time, gets the minimum).
  def height(seconds)
    return MIN_PX unless seconds

    raw = seconds * scale
    (raw <= MAX_PX ? [ raw, MIN_PX ].max : MAX_PX + (raw - MAX_PX) * 0.2).round
  end

  def self.for(ship, commits_result)
    user = ship.project&.user
    return unless commits_result.ok? && commits_result.commits.any? && user&.hackatime_linked? && ship.hackatime_projects.any?

    from = ship.project.hours_start
    to = ship.created_at || Time.current
    return unless from < to

    spans = Hackatime.heartbeat_spans(user, ship.hackatime_projects, start_date: from.utc.to_date - 1, end_date: to.utc.to_date + 2)
    new(commits_result.commits, spans, from:, to:, more: commits_result.more)
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    nil
  end

  # "1h 20m", "12m", "<1m".
  def self.format(seconds)
    minutes = (seconds / 60.0).round
    return (seconds.positive? ? "<1m" : "0m") if minutes.zero?

    hours, minutes = minutes.divmod(60)
    [ ("#{hours}h" if hours.positive?), ("#{minutes}m" if minutes.positive? || hours.zero?) ].compact.join(" ")
  end

  def initialize(commits, spans, from:, to:, more: false)
    @merged = merge(spans)
    previous = from
    @rows = commits.sort_by(&:date).each_with_index.to_h do |commit, index|
      row = if commit.date < from
        Row.new(commit, nil, :before_counting)
      elsif commit.date > to
        Row.new(commit, nil, :after_ship)
      else
        # The earliest commit listed, when GitHub cut the list: what came before it isn't known.
        seconds = seconds_between(previous, commit.date) unless more && index.zero?
        previous = commit.date
        Row.new(commit, seconds, nil)
      end
      [ commit, row ]
    end
    @tail_seconds = seconds_between(previous, to)
  end

  def row(commit) = @rows[commit]

  private
    # px a counted second takes: the total of the commits' counted time and the time after the last commit fills TIMELINE_PX.
    def scale
      @scale ||= begin
        total = @rows.each_value.sum { it.seconds.to_i } + @tail_seconds
        total.positive? ? TIMELINE_PX.fdiv(total) : 0
      end
    end

    # Overlapping spans (two projects at once) count each moment once.
    def merge(spans)
      spans.map { [ it["start_time"].to_f, it["end_time"].to_f ] }.select { it.last > it.first }.sort.each_with_object([]) do |(start, finish), merged|
        if merged.any? && start <= merged.last.last then merged.last[1] = [ merged.last.last, finish ].max
        else merged << [ start, finish ]
        end
      end
    end

    def seconds_between(from, to)
      from, to = from.to_f, to.to_f
      @merged.sum { |start, finish| [ [ finish, to ].min - [ start, from ].max, 0 ].max }.round
    end
end
