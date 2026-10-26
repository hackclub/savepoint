module StatsHelper
  # The growth charts' series: the row key, its legend label and the page's colour token for it. The hues are in a
  # fixed order (green, blue, orange, violet, yellow) that stays apart with colour blindness, and the stack order
  # is the legend order.
  GROWTH_STATE_SERIES = [
    { key: :current, label: "Current", color: "series-1" },
    { key: :new, label: "New", color: "series-2" },
    { key: :reactivated, label: "Reactivated", color: "series-3" },
    { key: :resurrected, label: "Resurrected", color: "series-4" }
  ].freeze
  GROWTH_AUDIENCE_SERIES = [
    { key: :dau, label: "DAU", color: "series-1" },
    { key: :wau, label: "WAU", color: "series-2" },
    { key: :mau, label: "MAU", color: "series-3" }
  ].freeze
  GROWTH_RATE_LABELS = {
    "curr" => "CURR", "nurr" => "NURR", "rurr" => "RURR", "surr" => "SURR", "iwaurr" => "iWAURR",
    "reactivation" => "Reactivation", "resurrection" => "Resurrection"
  }.freeze
  GROWTH_RATE_SERIES = [
    { key: :curr, label: "CURR", color: "series-1" },
    { key: :nurr, label: "NURR", color: "series-2" },
    { key: :rurr, label: "RURR", color: "series-3" },
    { key: :iwaurr, label: "iWAURR", color: "series-4" },
    { key: :surr, label: "SURR", color: "series-5" }
  ].freeze
  GROWTH_SIGNUP_LABELS = { "word_of_mouth" => "Word of mouth", "flat" => "Flat" }.freeze
  GROWTH_PROJECTION_COLORS = %w[series-2 series-3 series-4].freeze

  # DAU so far solid, then dashed projections: nothing changed, and each of the levers shown.
  def growth_projection_series(levers)
    [
      { key: :actual, label: "DAU so far", color: "ink", unlabelled: true },
      { key: :baseline, label: "Nothing changed", color: "series-1", dashed: true },
      *levers.zip(GROWTH_PROJECTION_COLORS).map do |lever, color|
        { key: lever[:rate].to_sym, label: "#{GROWTH_RATE_LABELS.fetch(lever[:rate])} up a tenth", color:, dashed: true }
      end
    ]
  end

  # Only the series with anything in them, so a legend never lists what hasn't happened (resurrected builders
  # need a month away). Each series keeps its own colour either way.
  def growth_series_present(series, rows)
    series.select { |one| rows.any? { |row| row[one[:key]].to_f.positive? } }
  end

  def stat_percent(rate)
    rate ? number_to_percentage(rate * 100, precision: 0) : "—"
  end

  # Line charts: each day of Save Point gets a slot, and a point sits at its centre, in a 1000 by 100 box that's
  # stretched to fit (so strokes are told not to scale).
  def stat_line_x(index, count) = ((index + 0.5) / count * 1000).round(1)
  def stat_line_y(value, axis_max) = (100 - value.to_f / axis_max * 100).round(1)

  # The runs of points a series draws, each as a polyline's points, broken where a day has no value.
  def stat_line_runs(rows, key, axis_max)
    rows.each_with_index.slice_when { |(before, _), (row, _)| before[key].nil? || row[key].nil? }
        .map { |run| run.reject { |row, _| row[key].nil? } }.reject(&:empty?)
        .map { |run| run.map { |row, index| "#{stat_line_x(index, rows.size)},#{stat_line_y(row[key], axis_max)}" }.join(" ") }
  end

  # Where each series ends, for its label: the last day it has a value. Labels that would sit on top of one
  # another are left off (the legend and tooltip have them), keeping the one with the higher series first; so is
  # a series marked `unlabelled` (DAU so far ends where the projections begin).
  def stat_line_ends(rows, series, axis_max)
    ends = series.filter_map do |one|
      next if one[:unlabelled]
      index = rows.rindex { |row| !row[one[:key]].nil? } or next
      { series: one, value: rows[index][one[:key]], x: (index + 0.5) / rows.size * 100, y: stat_line_y(rows[index][one[:key]], axis_max) }
    end
    ends.sort_by { |one| one[:y] }.each_with_object([]) do |one, kept|
      kept << one unless kept.any? { |other| (other[:x] - one[:x]).abs < 5 && (other[:y] - one[:y]).abs < 12 }
    end
  end

  def stat(value)
    number_with_delimiter(value)
  end

  def stat_share(share)
    share ? number_to_percentage(share * 100, precision: 0) : ""
  end

  # A round number at or above `max` (1, 2, 5, 10, 20, 50, …), for the top of an axis.
  def stat_axis_max(max)
    return 1 if max.to_f <= 0
    magnitude = 10**Math.log10(max).floor
    [ 1, 2, 5, 10 ].map { |step| step * magnitude }.find { |top| top >= max }
  end
end
