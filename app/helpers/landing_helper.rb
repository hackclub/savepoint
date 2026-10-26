module LandingHelper
  # One of the style sheet's icons (bin/rails style_sheet:sync), as the style sheet draws them: an SVG in the text's
  # colour, inside the <i data-icon> its bundle.js would have filled.
  def sp_icon(name, class_name = nil)
    tag.i(class: class_name, data: { icon: name }) do
      inline_svg_tag("save_point/icons/#{name}.svg", class: "sp-icon", aria_hidden: true, focusable: false)
    end
  end

  # One of the style sheet's colour icons (design/system/icons-color, built by design/build/make_color_icons.py and copied
  # by style_sheet:sync): the same MingCute icon as a chunky, glossy sticker in its own colours, like the hourglass coin.
  # Decorative, 48px or more: the text says what it stands for.
  def sp_color_icon(name, class_name = nil)
    tag.i(class: class_name, data: { color_icon: name }) do
      inline_svg_tag("save_point/icons-color/#{name}.svg", class: "sp-color-icon", aria_hidden: true, focusable: false)
    end
  end

  # Save Point's currency: the hourglass, for a price in hours.
  def hours_coin(alt: "") = image_tag("save_point/hours.png", alt:, class: "hours-coin", width: 121, height: 168)

  # How a prize's card is coloured in the shop: the cheapest third of the prizes by hours is common, the middle third
  # rare, the dearest third epic. The cuts come from Prize::ALL, so they follow the hours, and prizes with equal hours
  # always share a tier because the cuts are hours, not positions.
  def prize_tier(prize)
    rare_from, epic_from = prize_tier_cuts
    if prize.hours < rare_from then "common"
    elsif prize.hours < epic_from then "rare"
    else "epic"
    end
  end

  # The hours where rare and epic start: the hours of the prize a third and two thirds of the way along, cheapest first.
  def prize_tier_cuts
    hours = Prize::ALL.map(&:hours).sort
    [ hours[hours.size / 3], hours[hours.size * 2 / 3] ]
  end

  # The wave the prize cards' halftone starts under (_shop_shapes): across the panel from 0 to 1, how far down it is,
  # in the card's units. Armand set it, and the ramp below, in the metaball ramp editor on 2026-10-22
  # (https://claude.ai/artifact/YNUPuecR5o6Tvj7tcmksZz).
  SHOP_HALFTONE_WAVE = [ [ 0.0, 233 ], [ 0.3, 263 ], [ 0.72, 211 ], [ 0.78, 203 ], [ 1.0, 233 ] ].freeze

  # How big a dot is for its depth under the wave: depth as a share of the ramp's, against radius as a share of half
  # the grid step, so 1 would touch its neighbours. The dots stay small and apart at first, then swell toward the band.
  SHOP_HALFTONE_RAMP = [
    [ 0.0, 0.0 ], [ 0.085, 0.051 ], [ 0.18, 0.166 ], [ 0.293, 0.335 ], [ 0.507, 0.572 ], [ 0.777, 0.787 ], [ 1.0, 0.862 ]
  ].freeze

  # The halftone's dots, as [x, y, radius]: a hexagon grid, each dot sized by SHOP_HALFTONE_RAMP for its depth under
  # the wave. Each dot's depth is jittered a little, from a fixed seed so every render matches, so some neighbours
  # meet before others and the goo filter joins them in chains. It matches the editor dot for dot.
  def shop_halftone(left: 38, right: 362, top: 200, bottom: 372, wave: SHOP_HALFTONE_WAVE, step: 17, depth: 132, jitter: 0.47, min_radius: 1.2)
    random = mulberry32(7)
    ramp = monotone_spline(SHOP_HALFTONE_RAMP)
    (top..bottom).step(step * Math.sqrt(3) / 2).each_with_index.flat_map do |y, row|
      y = y.round(1)
      (left + (row.odd? ? step : step / 2.0)).step(right, step).filter_map do |x|
        depth_shade = (y - halftone_wave(wave, (x - left) / (right - left).to_f)) / depth
        shade = (depth_shade + (random.call - 0.5) * jitter * depth_shade.clamp(0, 1)).clamp(0, 1)
        radius = [ ramp.call(shade), 0 ].max * step / 2.0
        [ x.round(1), y, radius.round(2) ] if radius >= min_radius
      end
    end
  end

  # shop_halftone drawn wider than its panel: the dots of the plain call stay exactly as they are, and the grid carries
  # on `bleed` past each side and `bleed_bottom` below, so the panel's own clip cuts the pattern and no end or bottom
  # edge of it shows. `bleed` should be a multiple of `step`, so the extra dots sit on the same grid. The wave keeps its
  # place across the panel and runs flat beyond its two ends.
  def shop_halftone_bleed(bleed:, bleed_bottom:, left: 38, right: 362, bottom: 372, wave: SHOP_HALFTONE_WAVE, **options)
    base = shop_halftone(left: left, right: right, bottom: bottom, wave: wave, **options)
    wide_left, wide_right = left - bleed, right + bleed
    wide_wave = wave.map { |t, y| [ (left + t * (right - left) - wide_left) / (wide_right - wide_left).to_f, y ] }
    wide_wave = [ [ 0.0, wide_wave.first.last ], *wide_wave, [ 1.0, wide_wave.last.last ] ]
    extra = shop_halftone(left: wide_left, right: wide_right, bottom: bottom + bleed_bottom, wave: wide_wave, **options)
    base + extra.reject { |x, y, _| x.between?(left, right) && y <= bottom }
  end

  # The same halftone across the top of the claim popup (_claim), 400 wide and 240 tall, in white. The wave is the
  # card's, raised so the dots grow over the lower half and melt together under the popup's own wave.
  def claim_halftone = shop_halftone(left: 0, right: 400, top: 20, bottom: 240, wave: SHOP_HALFTONE_WAVE.map { |t, y| [ t, y - 150 ] })

  # The claim popup's own halftone: the same dots, 40 wider on each side (viewBox "-40 0 480 240"), so the card's
  # clip cuts the pattern and it never visibly ends. claim_halftone stays 400 wide for the buddy invite page.
  def claim_popup_halftone = shop_halftone(left: -40, right: 440, top: 20, bottom: 240, wave: SHOP_HALFTONE_WAVE.map { |t, y| [ t, y - 150 ] })

  CLAIM_BURST_COLORS = %w[var(--gold-hi) var(--gold) var(--gold-soft) var(--mint-hi) var(--violet-soft) var(--coral) var(--royal-soft)].freeze

  # The claim popup's celebration (_claim): each particle flies out from behind the popup, then drifts and fades. A
  # fixed seed makes every render match. Stars lead, so they come first and fly farthest; the last few only twinkle.
  def claim_burst
    rng = Random.new(2210)
    flying = (0...34).map do |i|
      kind = i < 11 ? :star : %i[spark dot bit].fetch(i % 3)
      angle = (i * 137.5 + rng.rand(-18.0..18.0)) * Math::PI / 180
      reach = rng.rand(190..440)
      { kind: kind, dx: (Math.cos(angle) * reach * 1.1).round, dy: (Math.sin(angle) * reach * 0.9 - 90).round,
        size: (kind == :star ? rng.rand(16..30) : rng.rand(6..16)), delay: rng.rand(0..260), spin: rng.rand(-300..300),
        color: kind == :star ? CLAIM_BURST_COLORS[i % 2] : CLAIM_BURST_COLORS.fetch(rng.rand(CLAIM_BURST_COLORS.size)) }
    end
    twinkles = [ [ -300, -170 ], [ 290, -210 ], [ -170, -330 ], [ 190, -330 ], [ -350, 40 ], [ 340, 20 ], [ 0, -390 ], [ -90, -250 ] ].each_with_index.map do |(dx, dy), i|
      { kind: :twinkle, dx: dx, dy: dy, size: rng.rand(14..24), delay: 700 + i * 260, spin: 0, color: CLAIM_BURST_COLORS[i % 3] }
    end
    flying + twinkles
  end

  # How far down `wave` is at `t` across the panel, eased between its points.
  def halftone_wave(wave, t)
    (a, from), (b, to) = wave.each_cons(2).find { |_, (b, _)| t <= b } || wave.last(2)
    from + (to - from) * (1 - Math.cos(Math::PI * (t - a) / (b - a))) / 2
  end

  # A monotone cubic (Fritsch–Carlson) through `points`, as the editor draws it: smooth, and never past either
  # neighbouring point's value.
  def monotone_spline(points)
    xs, ys = points.transpose
    slopes = xs.each_cons(2).zip(ys.each_cons(2)).map { |(x0, x1), (y0, y1)| (y1 - y0) / (x1 - x0) }
    tangents = [ slopes.first, *slopes.each_cons(2).map { |a, b| a * b <= 0 ? 0.0 : (a + b) / 2 }, slopes.last ]
    slopes.each_with_index do |slope, i|
      next tangents[i] = tangents[i + 1] = 0.0 if slope.zero?
      a, b = tangents[i] / slope, tangents[i + 1] / slope
      next if a * a + b * b <= 9
      k = 3 / Math.sqrt(a * a + b * b)
      tangents[i], tangents[i + 1] = k * a * slope, k * b * slope
    end
    lambda do |x|
      next ys.first if x <= xs.first
      next ys.last if x >= xs.last
      i = xs.index { |edge| x <= edge } - 1
      h = xs[i + 1] - xs[i]
      t = (x - xs[i]) / h
      t2 = t * t
      t3 = t2 * t
      (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * tangents[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * tangents[i + 1]
    end
  end

  # The editor's random numbers (mulberry32), so the site's jitter is the one Armand saw there.
  def mulberry32(seed)
    state = seed
    lambda do
      state = (state + 0x6D2B79F5) & 0xFFFFFFFF
      t = ((state ^ (state >> 15)) * (state | 1)) & 0xFFFFFFFF
      t ^= (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
      (t ^ (t >> 14)) / 4_294_967_296.0
    end
  end

  # 3.5 → "3.5", 5.0 → "5".
  def prize_hours(hours) = format("%g", hours)

  # "Oct 25", for the program's dates in sentences.
  def short_date(time) = time.strftime("%b %-d")

  # How long Save Point runs, in days.
  def run_days = ((Program::ENDS_AT - Program::STARTS_AT) / 1.day).round

  # Days from now (or the start, before it) to the end, as the goal panel counts them.
  def days_left = [ ((Program::ENDS_AT - [ Time.current, Program::STARTS_AT ].max) / 1.day).round, 1 ].max

  # "1 h 5 min", for the goal panel.
  def pace_text(minutes)
    hours, mins = minutes.divmod(60)
    [ ("#{hours} h" if hours.positive?), ("#{mins} min" if mins.positive?) ].compact.join(" ")
  end

  # A daily pace with its units small: "1 hr 5 min a day". The landing page's goal controller redraws it in the
  # browser, from the time there.
  def pace_html(minutes)
    hours, mins = minutes.divmod(60)
    parts = []
    parts << safe_join([ hours, tag.small(" hr") ]) if hours.positive?
    parts << safe_join([ mins, tag.small(" min") ]) if mins.positive?
    safe_join([ safe_join(parts, " "), tag.small(" a day") ])
  end

  # Where the landing page's buttons go: onboarding, where you sign in with Hack Club at the end, as Save Point's does. Someone
  # already signed in (reading /about) is not sent through sign-up again: it is their project, or onboarding where they left off.
  def landing_destination
    return onboarding_path unless signed_in?

    current_user.project ? project_path : onboarding_path
  end

  # The wording for a signed-in person with a project; everyone else keeps "Continue your game".
  def landing_cta_label
    signed_in? && current_user.project ? "Back to your project" : "Continue your game"
  end

  # The call to action, to landing_destination.
  def landing_cta(label = landing_cta_label, size: "lg", **options)
    classes = [ "sp-btn", "sp-btn--gold", ("sp-btn--#{size}" if size), "cta", options.delete(:class) ]
    link_to landing_destination, class: classes, **options do
      safe_join([ label, " ", sp_icon("play-fill") ])
    end
  end

  # The hero's call to action with the live sign-up count in it: "Join 12 people also finishing their game". With
  # nobody signed up it says "Continue your game". signups_controller.js polls /signups and swaps the two.
  def landing_join_cta(count, size: "lg")
    return landing_cta(size:, class: "cta--join") if signed_in?

    link_to onboarding_path, class: [ "sp-btn", "sp-btn--gold", ("sp-btn--#{size}" if size), "cta", "cta--join" ],
            data: { controller: "signups", signups_url_value: signups_path, signups_count_value: count } do
      safe_join([
        tag.span(hidden: count.zero?, data: { signups_target: "join" }) do
          safe_join([ "Join ", tag.span(count, class: "cta__num", data: { signups_target: "count" }), " ",
                      tag.span(count == 1 ? "person" : "people", data: { signups_target: "label" }), " also finishing their game" ])
        end,
        tag.span("Continue your game", hidden: count.positive?, data: { signups_target: "fallback" }),
        " ", sp_icon("play-fill")
      ])
    end
  end

  # "Wed Nov 4, 2026, 9:00 pm (UTC)": the end until the page's script puts it in your own time zone.
  def utc_end_text
    Program::ENDS_AT.strftime("%a %b %-d, %Y, %-l:%M %P (UTC)")
  end

  def landing_photos
    [
      [ "midnight.jpg", "About a hundred teenagers in a group photo under a big screen at Hack Club's Midnight event" ],
      [ "gadget.jpg", "Three teenagers smiling at a gadget one of them built" ],
      [ "tables.jpg", "Teenagers coding side by side at long tables during a Hack Club event" ],
      [ "hilltop.jpg", "A big group of Hack Clubbers waving on a hilltop at sunset" ],
      [ "campfire.jpg", "Teenagers around a campfire by the water at night" ],
      [ "breadboard.jpg", "Two teenagers laughing over a breadboard and a laptop" ]
    ]
  end

  # The small decorations in a zone's background, as real elements so they can move (landing.css, "Decorations"). Each
  # is [kind, colour, left %, top %, size px], positioned like the background-position they replaced. Every one gets its
  # own phase (--d), period (--p) and amplitude (--a) from a fixed seed, so nothing moves in lockstep and a reload
  # looks the same. Only transform and opacity animate, and reduced motion stills them.
  DECOR = {
    prizes: {
      wide: [ [ :spark, :white, 4, 30, 18 ], [ :spark, :white, 96, 44, 24 ], [ :spark, :white, 10, 78, 12 ], [ :spark, :white, 92, 86, 14 ],
              [ :spark, :white, 88, 14, 12 ], [ :cross, nil, 3, 58, 72 ], [ :cross, nil, 97, 22, 56 ], [ :dots, nil, 6, 10, 168 ], [ :dots, nil, 94, 91, 168 ] ],
      narrow: [ [ :spark, :white, 1, 9, 14 ], [ :spark, :white, 99, 24, 16 ], [ :spark, :white, 2, 62, 12 ], [ :spark, :white, 98, 88, 12 ] ]
    }
  }.freeze
  DECOR_DOTS = 12

  def landing_decor(zone)
    tag.div(class: [ "decor", "decor--#{zone}" ], aria: { hidden: true }) do
      safe_join(DECOR.fetch(zone).flat_map do |set, items|
        items.each_with_index.map { |item, index| decor_item(item, Random.new(zone.to_s.sum * 100 + set.to_s.sum + index), set) }
      end)
    end
  end

  def decor_item((kind, colour, left, top, size), rng, set)
    height = kind == :dots ? 8 : size
    place = "left: calc((100% - #{size}px) * #{left / 100.0}); top: calc((100% - #{height}px) * #{top / 100.0}); width: #{size}px; height: #{height}px"
    period = { spark: 2.6 + rng.rand * 2.4, cross: 36 + rng.rand * 24, dots: 3 + rng.rand }[kind].round(2)
    vars = "--p: #{period}s; --d: -#{(rng.rand * period).round(2)}s; --a: #{(0.16 + rng.rand * 0.2).round(2)}; --r: #{(8 + rng.rand * 14).round}deg; --s: #{rng.rand < 0.5 ? -1 : 1}"
    classes = [ "decor__item", "decor__#{kind}", ("decor__spark--#{colour}" if colour), "decor__set--#{set}" ]
    tag.span(class: classes, style: "#{place}; #{vars}") do
      safe_join(Array.new(DECOR_DOTS) { |i| tag.i(style: "--i: #{i}") }) if kind == :dots
    end
  end
end
