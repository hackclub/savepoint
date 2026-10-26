require "test_helper"

class Admin::ChartsHelperTest < ActionView::TestCase
  ZERO = { unapproved_hours: 0.0, pending_hours: 0.0, approved_hours: 0.0 }.freeze

  test "the hours bar has a segment for each stage that has hours, as wide as its share, with a 2px gap" do
    svg = Nokogiri::HTML.fragment(admin_funnel_bar(unapproved_hours: 1.0, pending_hours: 0.0, approved_hours: 3.0))
    paths = svg.css("path")

    assert_equal [ "admin-chart__stage admin-chart__stage--unapproved", "admin-chart__stage admin-chart__stage--approved" ], paths.map { |path| path["class"] }
    assert_equal [ "Unapproved: 1.0 h (25%)", "Approved: 3.0 h (75%)" ], svg.css("path title").map(&:text)
    assert_match(/Unapproved 1.0 h, 25%; Pending 0.0 h, 0%; Approved 3.0 h, 75%/, svg.at_css("svg")["aria-label"])
    (x1, w1), (x2, w2) = paths.map { |path| path["d"].match(/\AM([\d.]+) 0h([\d.]+)/).captures.map(&:to_f) }
    assert_equal 0.0, x1
    assert_in_delta 0.25, w1 / (w1 + w2), 0.001
    assert_in_delta 2, x2 - (x1 + w1), 0.01
  end

  test "with no hours at all the bar is one empty track, not a broken chart" do
    svg = Nokogiri::HTML.fragment(admin_funnel_bar(ZERO))

    assert_empty svg.css("path")
    assert_equal 1, svg.css("rect.admin-chart__track").size
    assert_equal [ 0.0 ], admin_funnel_stages(ZERO).map { |stage| stage[:share] }.uniq
  end

  test "each column has its date and value in a title, and a zero day has no column" do
    rows = [ { date: Date.new(2026, 10, 21), dau: 2 }, { date: Date.new(2026, 10, 22), dau: 0 }, { date: Date.new(2026, 10, 23), dau: 4 } ]
    svg = Nokogiri::HTML.fragment(admin_daily_chart(rows, :dau, unit: "builders"))

    assert_equal [ "Wed Oct 21: 2 builders", "Thu Oct 22: 0 builders", "Fri Oct 23: 4 builders" ], svg.css("g title").map(&:text)
    assert_equal 2, svg.css("path.admin-chart__column").size
    assert_match(/builders a day, Oct 21 to Oct 23: 2, 0, 4/, svg.at_css("svg")["aria-label"])
  end

  test "column heights are in proportion, the tallest filling the plot" do
    rows = [ { date: Date.new(2026, 10, 21), hours: 1.0 }, { date: Date.new(2026, 10, 22), hours: 2.0 } ]
    tops = Nokogiri::HTML.fragment(admin_daily_chart(rows, :hours, unit: "hours")).css("path.admin-chart__column").map { |path| path["d"][/\AM[\d.]+ [\d.]+V([\d.]+)A/, 1].to_f }
    plot = Admin::ChartsHelper::PLOT_HEIGHT
    heights = tops.map { |top| plot - (top - 4) }

    assert_in_delta plot, heights[1], 0.01
    assert_in_delta plot / 2.0, heights[0], 0.01
  end

  test "no finished days gives a plain note, not an empty svg" do
    assert_match(/No finished days yet/, admin_daily_chart([], :dau, unit: "builders"))
  end

  test "stacked columns stack the parts of a day, bottom first, with a 2px gap and the rounded end on top" do
    states = { new: 1, current: 3, reactivated: 0, resurrected: 0 }
    rows = [ { date: Date.new(2026, 10, 24), states: }, { date: Date.new(2026, 10, 25), states: { new: 0, current: 0, reactivated: 0, resurrected: 0 } } ]
    svg = Nokogiri::HTML.fragment(admin_stacked_chart(rows))

    assert_equal [ "admin-chart__column admin-chart__column--new", "admin-chart__column admin-chart__column--current" ], svg.css("path").map { |path| path["class"] }
    assert_equal [ "Sat Oct 24: 4 builders (1 new, 3 building most days, 0 back after a week, 0 back after a month)", "Sun Oct 25: 0 builders (0 new, 0 building most days, 0 back after a week, 0 back after a month)" ], svg.css("g title").map(&:text)
    heights = svg.css("path").map { |path| path["d"].scan(/\d+(?:\.\d+)?/).first(2).map(&:to_f) }
    assert_in_delta 96.0, heights[0][1], 0.01, "the first part stands on the baseline"
  end

  test "a column chart can fix its top and show a day with no value" do
    rows = [ { date: Date.new(2026, 10, 24), percent: 50 }, { date: Date.new(2026, 10, 25), percent: nil } ]
    svg = Nokogiri::HTML.fragment(admin_daily_chart(rows, :percent, unit: "% built", max: 100, title: ->(row) { "#{row[:date].day}: #{row[:percent] || "none"}" }))

    assert_equal [ "24: 50", "25: none" ], svg.css("g title").map(&:text)
    assert_equal 1, svg.css("path.admin-chart__column").size
  end

  test "dollars and waits read short" do
    assert_equal "$25", admin_dollars(25.0)
    assert_equal "$19.99", admin_dollars(19.99)
    now = Time.utc(2026, 10, 28, 12)
    assert_equal [ "5 min", "3 h", "3 days" ], [ now - 5.minutes, now - 3.hours, now - 3.days ].map { |time| admin_wait(time, now:) }
  end

  test "the biggest drop is the step that kept the smallest share, and none when nobody dropped" do
    steps = [ { key: "a", label: "A", count: 10, kept_percent: nil }, { key: "b", label: "B", count: 8, kept_percent: 80.0 },
              { key: "c", label: "C", count: 2, kept_percent: 25.0 }, { key: "d", label: "D", count: 0, kept_percent: nil } ]

    assert_equal "c", admin_biggest_drop(steps)[:key]
    assert_nil admin_biggest_drop([ steps[0], { key: "b", label: "B", count: 10, kept_percent: 100.0 } ])
  end

  test "funnel steps carry their bar width, what they were counted from, and the biggest drop" do
    funnel = { participants: 10, steps: [ { key: "signed_in", label: "Signed in", count: 10, kept_percent: nil },
                                          { key: "linked", label: "Linked Hackatime", count: 5, kept_percent: 50.0 },
                                          { key: "editor_sent", label: "Editor sent time", count: 1, kept_percent: 20.0 },
                                          { key: "set_up", label: "Picked a Hackatime project", count: 5, kept_percent: 100.0 } ] }
    steps = admin_funnel_steps(funnel)

    assert_equal [ 100.0, 50.0, 10.0, 50.0 ], steps.map { |step| step[:width] }
    assert_equal [ nil, "Signed in", "Linked Hackatime", "Linked Hackatime" ], steps.map { |step| step[:from] }, "picking is counted from linking"
    assert_equal [ false, false, true, false ], steps.map { |step| step[:biggest_drop] }
  end

  test "the biggest drop is only picked among the steps up to shipped, and ships in review aren't counted as lost" do
    steps = [ { key: "signed_in", label: "Signed in", count: 10, kept_percent: nil }, { key: "shipped", label: "Shipped", count: 4, lost: 6, kept_percent: 40.0 },
              { key: "approved", label: "Ship approved", count: 0, lost: 4, kept_percent: 0.0 }, { key: "claimed", label: "Claimed a prize", count: 0, lost: 0, kept_percent: nil } ]
    funnel = { participants: 10, steps: }
    drawn = admin_funnel_steps(funnel, { approved: 3, claimed: 0 })

    assert_equal "shipped", admin_biggest_drop(steps)[:key]
    assert_equal [ false, true, false, false ], drawn.map { |step| step[:biggest_drop] }
    assert_equal [ nil, 6, 1, 0 ], drawn.map { |step| step[:lost] }
    assert_equal [ 0, 0, 3, 0 ], drawn.map { |step| step[:waiting] }
    assert_equal "waiting for review", drawn[2][:waiting_text]
  end

  test "the hours bar stretches to its card" do
    svg = Nokogiri::HTML.fragment(admin_funnel_bar(unapproved_hours: 1.0, pending_hours: 1.0, approved_hours: 1.0)).at_css("svg")

    assert_equal "none", svg["preserveaspectratio"]
  end

  test "with nobody signed in every bar is 0 wide" do
    funnel = { participants: 0, steps: [ { key: "signed_in", label: "Signed in", count: 0, kept_percent: nil } ] }

    assert_equal [ 0.0 ], admin_funnel_steps(funnel).map { |step| step[:width] }
  end
end
