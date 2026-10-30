require "test_helper"

# D-126
class Ship::CommitTimesTest < ActiveSupport::TestCase
  FROM = Time.utc(2026, 11, 10, 12)
  TO = Time.utc(2026, 11, 10, 18)

  def commit(sha, time) = Ship::Commits::Commit.new(sha:, message: sha, author: "Ana", date: time, url: "u")
  def span(from, to) = { "start_time" => from.to_f, "end_time" => to.to_f, "duration" => (to - from).to_i }
  def times(commits, spans, more: false) = Ship::CommitTimes.new(commits, spans, from: FROM, to: TO, more:)

  test "a span that crosses a commit is split between the two intervals, and the tail is the rest" do
    first, second = commit("aaaaaaa", FROM + 1.hour), commit("bbbbbbb", FROM + 3.hours)
    result = times([ second, first ], [ span(FROM + 30.minutes, FROM + 90.minutes), span(FROM + 2.hours, FROM + 4.hours) ])

    assert_equal 30.minutes.to_i, result.row(first).seconds, "only the half of the first span before the commit"
    assert_equal 30.minutes.to_i + 1.hour.to_i, result.row(second).seconds, "the other half, and the second span up to the commit"
    assert_equal 1.hour.to_i, result.tail_seconds, "the rest of the second span, after the last commit"
  end

  test "the figures add up to the time over the whole window" do
    commits = [ commit("aaaaaaa", FROM + 1.hour), commit("bbbbbbb", FROM + 3.hours) ]
    spans = [ span(FROM - 1.hour, FROM + 90.minutes), span(FROM + 2.hours, TO + 1.hour) ]
    result = times(commits, spans)

    total = result.rows.values.sum(&:seconds) + result.tail_seconds
    assert_equal 90.minutes.to_i + 4.hours.to_i, total, "time before the start and after the ship is not counted"
  end

  test "overlapping spans count each moment once" do
    first = commit("aaaaaaa", FROM + 2.hours)
    result = times([ first ], [ span(FROM, FROM + 1.hour), span(FROM + 30.minutes, FROM + 90.minutes) ])
    assert_equal 90.minutes.to_i, result.row(first).seconds
  end

  test "commits outside the window are labelled and take no time" do
    early, inside, late = commit("aaaaaaa", FROM - 1.hour), commit("bbbbbbb", FROM + 1.hour), commit("ccccccc", TO + 1.hour)
    result = times([ late, inside, early ], [ span(FROM - 2.hours, TO + 2.hours) ])

    assert_equal [ nil, :before_counting ], [ result.row(early).seconds, result.row(early).label ]
    assert_equal [ nil, :after_ship ], [ result.row(late).seconds, result.row(late).label ]
    assert_equal [ 1.hour.to_i, nil ], [ result.row(inside).seconds, result.row(inside).label ], "its interval starts at the window, not at the earlier commit"
    assert_equal 5.hours.to_i, result.tail_seconds
  end

  test "when GitHub cut the list, the earliest commit's figure is unknown" do
    first, second = commit("aaaaaaa", FROM + 1.hour), commit("bbbbbbb", FROM + 2.hours)
    result = times([ second, first ], [ span(FROM, TO) ], more: true)

    assert_nil result.row(first).seconds
    assert_nil result.row(first).label
    assert_equal 1.hour.to_i, result.row(second).seconds
    assert_equal 4.hours.to_i, result.tail_seconds
  end

  test "an untruncated list gives the first commit the time since the start" do
    first = commit("aaaaaaa", FROM + 1.hour)
    assert_equal 1.hour.to_i, times([ first ], [ span(FROM, TO) ]).row(first).seconds
  end

  test "formats seconds as hours and minutes" do
    assert_equal [ "0m", "<1m", "12m", "1h", "1h 20m" ], [ 0, 20, 12 * 60, 3600, 4800 ].map { Ship::CommitTimes.format(it) }
  end
end
