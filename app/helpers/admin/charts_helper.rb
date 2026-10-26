# The charts on the admin home (/admin), drawn on the server as inline SVG in the site's own colour tokens: a split bar
# (the hours funnel, how many are on pace, what prizes cost), a column chart for a number day by day, and stacked columns
# for one that splits. Every mark has a <title> for hover, and each chart has its numbers beside it as text, so nothing
# rests on colour alone. The participants' funnel is a list of bars, each with its count and what it lost.
module Admin::ChartsHelper
  FUNNEL_STAGES = {
    unapproved: { name: "Unapproved", key: :unapproved_hours, about: "built, not shipped yet" },
    pending: { name: "Pending", key: :pending_hours, about: "awaiting review" },
    approved: { name: "Approved", key: :approved_hours, about: "approved by a reviewer" }
  }.freeze
  # The states someone builds in, as Growth names them, bottom of a column first.
  BUILD_STATES = [ { key: :new, id: "new", name: "New" }, { key: :current, id: "current", name: "Building most days" },
                   { key: :reactivated, id: "reactivated", name: "Back after a week" }, { key: :resurrected, id: "resurrected", name: "Back after a month" } ].freeze
  BAR_WIDTH = 400
  BAR_HEIGHT = 36
  PLOT_WIDTH = 300
  PLOT_HEIGHT = 96
  GAP = 2
  CORNER = 4

  # The stages with their hours and their share of all the hours (0 when there are none).
  def admin_funnel_stages(summary)
    total = FUNNEL_STAGES.values.sum { |stage| summary.fetch(stage[:key]) }.to_f
    FUNNEL_STAGES.map do |id, stage|
      hours = summary.fetch(stage[:key])
      stage.merge(id:, hours:, share: total.zero? ? 0.0 : hours / total)
    end
  end

  # The hours funnel as a split bar.
  def admin_funnel_bar(summary)
    admin_split_bar(admin_funnel_stages(summary).map { |stage| { id: stage[:id], name: stage[:name], value: stage[:hours], text: "#{admin_hours(stage[:hours])} h" } })
  end

  # One bar split into parts ({ id:, name:, value:, text: }), each as wide as its share of the values, with a 2px gap
  # between. With nothing in any, an empty track. Square-ended: the page rounds its ends in CSS (so the corner is 4px at
  # any width) by clipping the svg. It stretches to fill its card: its height is fixed in CSS, and it has no round parts to distort.
  def admin_split_bar(parts)
    total = parts.sum { |part| part[:value] }.to_f
    shares = parts.map { |part| total.zero? ? 0.0 : part[:value] / total }
    drawn = parts.zip(shares).select { |_, share| share.positive? }
    label = parts.zip(shares).map { |part, share| "#{part[:name]} #{part[:text]}, #{admin_share(share)}" }.join("; ")
    tag.svg(class: "admin-chart__funnel", viewBox: "0 0 #{BAR_WIDTH} #{BAR_HEIGHT}", preserveAspectRatio: "none", role: "img", aria: { label: }) do
      if drawn.empty?
        tag.rect(tag.title("Nothing yet"), class: "admin-chart__track", width: BAR_WIDTH, height: BAR_HEIGHT)
      else
        room = BAR_WIDTH - GAP * (drawn.size - 1)
        x = 0.0
        safe_join(drawn.map do |part, share|
          width = (room * share).round(2)
          mark = "M#{x.round(2)} 0h#{width}v#{BAR_HEIGHT}h-#{width}Z"
          x += width + GAP
          tag.path(tag.title("#{part[:name]}: #{part[:text]} (#{admin_share(share)})"), class: "admin-chart__stage admin-chart__stage--#{part[:id]}", d: mark)
        end)
      end
    end
  end

  # A column chart of one number a day. `rows` are the daily rows and `key` the number in them (nil is a day with nothing
  # to show). Every column has its date and value in a <title> (or `title.call(row)`), with a taller invisible target
  # behind it so a short column is still easy to hover. `max` fixes the top of the plot (100 for a percentage).
  def admin_daily_chart(rows, key, unit:, max: nil, title: nil)
    return tag.p("No finished days yet.", class: "admin-chart__empty") if rows.empty?

    values = rows.map { |row| row.fetch(key) }
    top = (max || [ values.compact.max.to_f, 1 ].max).to_f
    slot = PLOT_WIDTH.to_f / rows.size
    width = [ slot - GAP, 1 ].max.round(2)
    label = "#{unit} a day, #{admin_chart_date(rows.first[:date])} to #{admin_chart_date(rows.last[:date])}: #{values.map { |value| value.nil? ? "none" : value }.join(", ")}"
    tag.svg(class: "admin-chart__columns", viewBox: "0 0 #{PLOT_WIDTH} #{PLOT_HEIGHT}", role: "img", aria: { label: }) do
      marks = rows.each_with_index.map do |row, index|
        value = values[index]
        height = value.to_f.zero? ? 0 : [ PLOT_HEIGHT * value / top, 2 ].max.round(2)
        x = (index * slot + GAP / 2.0).round(2)
        tag.g(class: "admin-chart__day") do
          tag.title(title ? title.call(row) : "#{row[:date].strftime("%a %b %-d")}: #{number_with_delimiter(value)} #{unit}") +
            tag.rect(class: "admin-chart__hit", x:, y: 0, width:, height: PLOT_HEIGHT) +
            (height.positive? ? tag.path(class: "admin-chart__column", d: column_path(x, width, height, PLOT_HEIGHT)) : "".html_safe)
        end
      end
      safe_join([ *marks, tag.line(class: "admin-chart__base", x1: 0, x2: PLOT_WIDTH, y1: PLOT_HEIGHT, y2: PLOT_HEIGHT) ])
    end
  end

  # Columns a day split into `series` ([ { key:, id:, name: } ], bottom first), each row holding the parts in row[:states].
  # The parts stack with a 2px gap between, and the top one has the rounded end.
  def admin_stacked_chart(rows, series: BUILD_STATES, unit: "builders")
    return tag.p("No finished days yet.", class: "admin-chart__empty") if rows.empty?

    totals = rows.map { |row| series.sum { |part| row[:states].fetch(part[:key]) } }
    top = [ totals.max, 1 ].max.to_f
    slot = PLOT_WIDTH.to_f / rows.size
    width = [ slot - GAP, 1 ].max.round(2)
    label = "#{unit} a day, #{admin_chart_date(rows.first[:date])} to #{admin_chart_date(rows.last[:date])}: #{totals.join(", ")}"
    tag.svg(class: "admin-chart__columns", viewBox: "0 0 #{PLOT_WIDTH} #{PLOT_HEIGHT}", role: "img", aria: { label: }) do
      marks = rows.each_with_index.map do |row, index|
        x = (index * slot + GAP / 2.0).round(2)
        parts = series.select { |part| row[:states].fetch(part[:key]).positive? }
        floor = PLOT_HEIGHT.to_f
        segments = parts.each_with_index.map do |part, at|
          value = row[:states].fetch(part[:key])
          height = [ (PLOT_HEIGHT - GAP * (parts.size - 1)) * value / top, 2 ].max.round(2)
          path = at == parts.size - 1 ? column_path(x, width, height, floor) : "M#{x} #{floor.round(2)}V#{(floor - height).round(2)}h#{width}V#{floor.round(2)}Z"
          floor -= height + GAP
          tag.path(class: "admin-chart__column admin-chart__column--#{part[:id]}", d: path)
        end
        detail = series.map { |part| "#{row[:states].fetch(part[:key])} #{part[:name].downcase}" }.join(", ")
        tag.g(class: "admin-chart__day") do
          tag.title("#{row[:date].strftime("%a %b %-d")}: #{totals[index]} #{unit} (#{detail})") +
            tag.rect(class: "admin-chart__hit", x:, y: 0, width:, height: PLOT_HEIGHT) + safe_join(segments)
        end
      end
      safe_join([ *marks, tag.line(class: "admin-chart__base", x1: 0, x2: PLOT_WIDTH, y1: PLOT_HEIGHT, y2: PLOT_HEIGHT) ])
    end
  end

  # The funnel steps ready to draw: each with how wide its bar is (its share of everyone who signed in), what it was
  # counted from, and whether it's the biggest drop.
  # `waiting` (ParticipantFunnel.waiting) says how many at the last two steps are waiting, not lost: ships in review at
  # "Ship approved", approved ones who haven't claimed at "Claimed a prize". Each step gets `waiting` and `lost`
  # (the funnel's lost less those waiting).
  def admin_funnel_steps(funnel, waiting = {})
    steps = funnel.fetch(:steps)
    signed_in = funnel.fetch(:participants)
    worst = admin_biggest_drop(steps)
    steps.each_with_index.map do |step, index|
      from = steps.find { |other| other[:key] == ParticipantFunnel::AFTER[step[:key]] } || steps[index - 1] unless index.zero?
      waits = step[:key] == "approved" ? waiting[:approved].to_i : step[:key] == "claimed" ? waiting[:claimed].to_i : 0
      waiting_text = { "approved" => "waiting for review", "claimed" => "haven't claimed yet" }[step[:key]]
      step.merge(width: signed_in.zero? ? 0.0 : (100.0 * step[:count] / signed_in).round(1), from: from&.fetch(:label), biggest_drop: step.equal?(worst),
                 waiting: waits, waiting_text:, lost: step[:lost] && [ step[:lost] - waits, 0 ].max)
    end
  end

  # The step that kept the smallest share of the people before it, among the steps up to and including `through` (the ones
  # the participant controls: after that, people are waiting on a review or a prize, not lost) that have someone before
  # them. Nil when nobody dropped anywhere. The earlier step wins a tie.
  def admin_biggest_drop(steps, through: "shipped")
    last = steps.index { |step| step[:key] == through } || steps.size - 1
    worst = steps.first(last + 1).select { |step| step[:kept_percent] }.min_by { |step| step[:kept_percent] }
    worst if worst && worst[:kept_percent] < 100
  end

  # "Oct 21", for the axis under a chart.
  def admin_chart_date(date) = date.strftime("%b %-d")

  def admin_hours(hours) = number_with_precision(hours, precision: 1, delimiter: ",")

  def admin_share(fraction) = number_to_percentage(fraction * 100, precision: 0)

  def admin_dollars(amount) = number_to_currency(amount, precision: amount.to_f == amount.to_f.round ? 0 : 2)

  # "3 h", "40 min", "2 days": how long ago `time` was, for the oldest ship waiting.
  def admin_wait(time, now: Time.current)
    seconds = (now - time).to_i
    return "#{[ seconds / 60, 1 ].max} min" if seconds < 1.hour
    return "#{seconds / 3600} h" if seconds < 2.days

    "#{seconds / 1.day} days"
  end

  private
    # A column `width` wide and `height` tall from x, standing on `base`, with its top corners rounded (4px, less on a
    # thin or short mark) and its foot square on the baseline.
    def column_path(x, width, height, base)
      r = [ CORNER, width / 2.0, height / 2.0 ].min.round(2)
      y = (base - height).round(2)
      x2 = (x + width).round(2)
      "M#{x} #{base.round(2)}V#{y + r}A#{r} #{r} 0 0 1 #{x + r} #{y}H#{x2 - r}A#{r} #{r} 0 0 1 #{x2} #{y + r}V#{base.round(2)}Z"
    end
end
