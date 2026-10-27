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

  attr_reader :claimed, :ai_coding, :art, :lapse, :lapse_coding

  def initialize(claimed:, ai_coding_seconds:, art_seconds:, lapse_seconds: nil, lapse_coding_hours: 0)
    @claimed = [ claimed.to_d, 0 ].max
    @ai_known = !ai_coding_seconds.nil?
    @art_known = !art_seconds.nil?
    @ai_coding = [ hours(ai_coding_seconds), @claimed ].min
    # Lapse time is part of the art time. Unknown (nil) Lapse time can't be split, so nothing moves.
    @lapse = lapse_seconds.nil? || !@art_known ? 0.to_d : [ hours(lapse_seconds), hours(art_seconds) ].min
    @lapse_coding = [ lapse_coding_hours.to_d, 0, @lapse ].sort[1]
    @art = [ [ hours(art_seconds) - @lapse_coding, @claimed - @ai_coding - @lapse_coding ].min, 0 ].max
  end

  def lapse_known? = @art_known && @lapse.positive?

  def ai_known? = @ai_known
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

  # The coding and art hours the reviewer asked for, held to the limits as playground's approve_review! does: coding
  # to the AI cap, art to the art hold on that coding. nil asks for the most; a figure within a rounding of the most is
  # the most. Returns [coding, art, below], where below says the reviewer went under what the rules allow, so "why
  # deflated" is due. The AI cut and the art hold need no reason. Both figures are rounded down to the hundredth.
  def approve(coding_hours, art_hours)
    top_coding = coding_cap.floor(2)
    coding = coding_hours.nil? ? top_coding : coding_hours.to_d.clamp(0, top_coding)
    coding = top_coding if top_coding - coding < TOLERANCE
    top_art = art_allowed_for(coding).floor(2)
    art = art_hours.nil? ? top_art : art_hours.to_d.clamp(0, top_art)
    art = top_art if top_art - art < TOLERANCE
    [ coding, art, top_coding - coding >= TOLERANCE || top_art - art >= TOLERANCE ]
  end

  # D-097: a later ship's review judges only the new hours, with the limits read on the whole project. These hold what the
  # earlier approval (its cumulative coding and art) already used. The most new coding is the cumulative coding cap less the
  # earlier coding, and the most new art is the art hold on the cumulative coding less the earlier art. Never below 0.
  def new_coding_top(earlier_coding) = [ coding_cap.floor(2) - earlier_coding.to_d, 0 ].max
  def new_art_top(earlier_coding, earlier_art, new_coding) = [ art_allowed_for(earlier_coding.to_d + new_coding.to_d).floor(2) - earlier_art.to_d, 0 ].max
  def new_art_claimed(earlier_art) = [ art - earlier_art.to_d, 0 ].max
  def new_coding_claimed(earlier_coding) = [ coding - earlier_coding.to_d, 0 ].max

  # approve, for the new hours of a later ship. Returns [new coding, new art, below].
  def approve_new(earlier_coding, earlier_art, coding_hours, art_hours)
    top_coding = new_coding_top(earlier_coding)
    coding = coding_hours.nil? ? top_coding : coding_hours.to_d.clamp(0, top_coding)
    coding = top_coding if top_coding - coding < TOLERANCE
    top_art = new_art_top(earlier_coding, earlier_art, coding)
    art = art_hours.nil? ? top_art : art_hours.to_d.clamp(0, top_art)
    art = top_art if top_art - art < TOLERANCE
    [ coding, art, top_coding - coding >= TOLERANCE || top_art - art >= TOLERANCE ]
  end

  def ai_cut = coding - coding_cap
  def art_cut = art - art_allowed
  def cut? = claimed - most >= TOLERANCE

  # Why the limits cut, for the reviewer to keep or rewrite as the deflation reason. nil when they cut nothing.
  def reason
    parts = []
    if ai_cut >= TOLERANCE
      parts << "Hackatime has #{self.class.hrs(ai_coding)} of AI coding on this game, which counts at a third " \
               "(#{self.class.hrs(ai_coding / 3)})."
    end
    if art_cut >= TOLERANCE
      parts << "Hackatime has #{self.class.hrs(art)} of art (designing and Lapse#{", not counting the Lapse coding" if lapse_coding.positive?}), " \
               "which counts at most #{ART_CAP_PERCENT}% of the approved hours (#{self.class.hrs(art_allowed)})."
    end
    parts.join(" ").presence
  end

  # 5.71, or 4 rather than 4.0
  def self.format(hours) = hours.to_d.round(2).to_s("F").delete_suffix(".0")

  # "1 hr", "5.71 hrs"
  def self.hrs(hours) = "#{format(hours)} #{format(hours) == "1" ? "hr" : "hrs"}"

  private
    def hours(seconds) = seconds.to_i.to_d / 3600
end
