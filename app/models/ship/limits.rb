# The most hours a ship can be approved for under the handbook's limits (D-030), worked out as playground does
# (Ship#ai_cap_seconds and #art_allowed_seconds there). All the time is Hackatime's, so the claimed hours split into
# art (Hackatime's "designing" category and Lapse's "timelapsing", D-042) and coding (the rest). "ai coding" time is
# part of coding and counts at a third. Art counts at most ART_CAP_PERCENT of the approved total. Unknown category time (nil) cuts nothing.
# D-085: the reviewer may call some of the Lapse hours coding (an editor Hackatime can't track). Those leave art and join
# coding, so they sit outside the art cap. The rest of the Lapse hours and "designing" stay under it.
#
#   claimed 10, ai coding 3, art 4: coding 6, coding cap 6 - 3 * 2/3 = 4, art at most 4 * 30/70 = 1.71, most 5.71
#   the same with 3 of the art being Lapse coding: art 1, coding 9, coding cap 9 - 2 = 7, art at most 3, most 8
class Ship::Limits
  ART_CAP_PERCENT = 30
  # Under this many hours apart is form rounding, not a cut.
  TOLERANCE = BigDecimal("0.01")

  attr_reader :claimed, :ai_coding, :hackatime_ai, :reviewer_ai, :art, :lapse, :lapse_coding

  # D-102: reviewer_ai_hours is the AI coding time the reviewer set (nil when none). The limits use the larger of that and
  # Hackatime's figure, never more than the claimed hours. D-111: the claimed hours are read to the hundredth, as the
  # decimal(6,2) column keeps them, so the most the rules allow is measured from the figure that is stored.
  def initialize(claimed:, ai_coding_seconds:, art_seconds:, lapse_seconds: nil, lapse_coding_hours: 0, reviewer_ai_hours: nil)
    @claimed = [ claimed.to_d.round(2), 0 ].max
    @reviewer_ai = reviewer_ai_hours&.to_d
    @ai_known = !ai_coding_seconds.nil? || !@reviewer_ai.nil?
    @art_known = !art_seconds.nil?
    @hackatime_ai = [ hours(ai_coding_seconds), @claimed ].min
    @ai_coding = [ [ hours(ai_coding_seconds), @reviewer_ai || 0 ].max, @claimed ].min
    # Lapse time is part of the art time. Unknown (nil) Lapse time can't be split, so nothing moves.
    @lapse = lapse_seconds.nil? || !@art_known ? 0.to_d : [ hours(lapse_seconds), hours(art_seconds) ].min
    @lapse_coding = [ lapse_coding_hours.to_d, 0, @lapse ].sort[1]
    @art = [ [ hours(art_seconds) - @lapse_coding, @claimed - @ai_coding - @lapse_coding ].min, 0 ].max
  end

  def lapse_known? = @art_known && @lapse.positive?

  def ai_known? = @ai_known

  # D-102: the reviewer's figure is above Hackatime's, so it is the one in force.
  def ai_raised? = ai_coding - hackatime_ai >= TOLERANCE
  def art_known? = @art_known
  def known? = ai_known? && art_known?

  def coding = claimed - art

  # Coding less two thirds of its AI time.
  def coding_cap = [ coding - ai_coding * 2 / 3, 0 ].max

  # Art at ART_CAP_PERCENT of coding plus art.
  def art_max = coding_cap * ART_CAP_PERCENT / (100 - ART_CAP_PERCENT)
  def art_allowed = [ art, art_max ].min

  # The most art that counts beside this much approved coding, and the art that does (D-063: the reviewer sets coding and
  # art apart, and the art hold moves with the coding).
  def art_max_for(coding) = coding * ART_CAP_PERCENT / (100 - ART_CAP_PERCENT)
  def art_allowed_for(coding) = [ art, art_max_for(coding) ].min

  # Rounded down to the hundredth, so it never passes a limit.
  def most = (coding_cap + art_allowed).floor(2)

  # D-111: the coding and art figures that add up to `most`. Each rounds down to the hundredth on its own, and the two floors can
  # sit a hundredth under it (coding 3.76 and art 1.53 make 5.29 under 5.30). That hundredth goes to the part that lost the
  # larger share of one in its rounding, so approving the most stores exactly `most`, which is the claimed hours when
  # nothing is cut.
  def coding_top
    low = coding_cap.floor(2)
    carried = most - low - art_allowed.floor(2)
    carried.positive? && coding_cap - low >= art_allowed - art_allowed.floor(2) ? low + carried : low
  end

  # The most art that counts beside this much approved coding. At the top coding it is what is left of `most`, and below it the
  # art hold on that coding, rounded down.
  def art_top(coding) = coding >= coding_top ? [ most - coding, 0 ].max : art_allowed_for(coding).floor(2)

  # The coding and art hours the reviewer asked for, held to the limits as playground's approve_review! does: coding
  # to the AI cap, art to the art hold on that coding. nil asks for the most; a figure within a rounding of the most is
  # the most. Returns [coding, art, below], where below says the reviewer went under what the rules allow, so "why
  # deflated" is due. The AI cut and the art hold need no reason. Both figures are in hundredths.
  def approve(coding_hours, art_hours) = approve_new(0, 0, coding_hours, art_hours)

  # D-097: a later ship's review judges only the new hours, with the limits read on the whole project. These hold what the
  # earlier approval (its cumulative coding and art) already used. The most new coding is the cumulative coding top less the
  # earlier coding, and the most new art is the art top on the cumulative coding less the earlier art. Both are kept to what is
  # left of `most` (D-111), so the total never passes it whichever way an earlier approval was rounded. Never below 0.
  def new_coding_top(earlier_coding, earlier_art = 0) = [ [ coding_top - earlier_coding.to_d, 0 ].max, [ most - earlier_coding.to_d - earlier_art.to_d, 0 ].max ].min
  def new_art_top(earlier_coding, earlier_art, new_coding) = [ art_top(earlier_coding.to_d + new_coding.to_d) - earlier_art.to_d, 0 ].max
  def new_art_claimed(earlier_art) = [ art - earlier_art.to_d, 0 ].max
  def new_coding_claimed(earlier_coding) = [ coding - earlier_coding.to_d, 0 ].max

  # approve, for the new hours of a later ship. Returns [new coding, new art, below].
  def approve_new(earlier_coding, earlier_art, coding_hours, art_hours)
    top_coding = new_coding_top(earlier_coding, earlier_art)
    coding = typed(coding_hours, top_coding)
    top_art = new_art_top(earlier_coding, earlier_art, coding)
    art = typed(art_hours, top_art)
    [ coding, art, top_coding - coding >= TOLERANCE || top_art - art >= TOLERANCE ]
  end

  def ai_cut = coding - coding_cap
  def art_cut = art - art_allowed

  # D-111: `most` rounds down, so a cut of any size, a few seconds of AI coding even, takes at least a hundredth off the stored
  # total. Whatever lowers it is a deflation, and has to be named (#reason).
  def cut? = claimed > most

  # Why the limits cut, for the reviewer to keep or rewrite as the deflation reason. Each cut that lowers the total is named,
  # however small. nil when they cut nothing.
  def reason = [ ai_reason, art_reason ].compact.join(" ").presence

  # 5.71, or 4 rather than 4.0. An amount under a hundredth keeps two digits (0.0028), so a cut that small still reads as one.
  def self.format(hours)
    hours = hours.to_d
    (hours.positive? && hours < TOLERANCE ? hours.round(2 - hours.exponent) : hours.round(2)).to_s("F").delete_suffix(".0")
  end

  # "1 hr", "5.71 hrs"
  def self.hrs(hours) = "#{format(hours)} #{format(hours) == "1" ? "hr" : "hrs"}"

  private
    def hours(seconds) = seconds.to_i.to_d / 3600

    # A figure the reviewer typed, held between 0 and its top and kept to the hundredth. nil is the top, and so is a figure
    # within a rounding of it.
    def typed(figure, top)
      value = figure.nil? ? top : figure.to_d.clamp(0, top)
      top - value < TOLERANCE ? top : value.round(2)
    end

    def ai_reason
      return unless ai_cut.positive?

      if ai_raised?
        "Hackatime has #{self.class.hrs(hackatime_ai)} of AI coding on this game, and the reviewer raised it to #{self.class.hrs(ai_coding)}, " \
          "which counts at a third (#{self.class.hrs(ai_coding / 3)})."
      else
        "Hackatime has #{self.class.hrs(ai_coding)} of AI coding on this game, which counts at a third (#{self.class.hrs(ai_coding / 3)})."
      end
    end

    def art_reason
      return unless art_cut.positive?

      "Hackatime has #{self.class.hrs(art)} of art (designing and Lapse#{", not counting the Lapse coding" if lapse_coding.positive?}), " \
        "which counts at most #{ART_CAP_PERCENT}% of the approved hours (#{self.class.hrs(art_allowed)})."
    end
end
