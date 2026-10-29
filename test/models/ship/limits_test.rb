require "test_helper"

# The handbook's limits (D-030): AI coding at a third, art at most 30% of the approved total.
class Ship::LimitsTest < ActiveSupport::TestCase
  def limits(claimed, ai: 0, art: 0) = Ship::Limits.new(claimed:, ai_coding_seconds: ai && (ai * 3600).round, art_seconds: art && (art * 3600).round)

  test "the worked example: 10 counted, 3 of AI coding, 4 of art" do
    l = limits(10, ai: 3, art: 4)
    assert_equal 6, l.coding
    assert_equal 4, l.coding_cap, "6 of coding less two thirds of 3"
    assert_equal BigDecimal("1.71"), l.art_allowed.floor(2), "art at 30% of the total: 4 * 30 / 70"
    assert_equal BigDecimal("5.71"), l.most, "rounded down, never past a limit"
    assert l.cut?
    assert_equal "Hackatime has 3 hrs of AI coding on this game, which counts at a third (1 hr). " \
                 "Hackatime has 4 hrs of art (designing and Lapse), which counts at most 30% of the approved hours (1.71 hrs).", l.reason
  end

  test "no AI coding and art within its share cut nothing" do
    l = limits(10, ai: 0, art: 3)
    assert_equal 10, l.most
    assert_not l.cut?
    assert_nil l.reason
  end

  test "AI coding alone counts at a third" do
    l = limits(9, ai: 9)
    assert_equal 3, l.most
    assert_match "AI coding", l.reason
    assert_no_match "art", l.reason
  end

  test "art alone is held to 30% of the total, so all-art time approves nothing" do
    assert_equal 0, limits(5, art: 5).most
    l = limits(10, art: 6)
    assert_equal 4, l.coding
    assert_equal BigDecimal("5.71"), l.most, "4 of coding and 1.71 of art"
  end

  test "category time past the hours that count is held to them" do
    l = limits(2, ai: 5, art: 5)
    assert_equal 2, l.ai_coding
    assert_equal 0, l.art, "art only fills what AI coding left"
    assert_equal BigDecimal("0.66"), l.most
  end

  test "unknown category time cuts nothing, and says it's unknown" do
    l = limits(8, ai: nil, art: nil)
    assert_not l.known?
    assert_not l.ai_known?
    assert_equal 8, l.most
    assert limits(8, ai: 1, art: nil).ai_known?
    assert_not limits(8, ai: 1, art: nil).known?
  end

  # D-085: Lapse hours the reviewer calls coding leave art and join coding, outside the cap.
  def lapse_limits(claimed, ai: 0, art: 0, lapse: 0, coding: 0)
    Ship::Limits.new(claimed:, ai_coding_seconds: (ai * 3600).round, art_seconds: (art * 3600).round,
                     lapse_seconds: (lapse * 3600).round, lapse_coding_hours: coding)
  end

  test "Lapse coding defaults to 0, so all Lapse time is art and nothing changes" do
    l = lapse_limits(10, ai: 3, art: 4, lapse: 3)
    assert_equal 0, l.lapse_coding
    assert_equal 4, l.art
    assert_equal BigDecimal("5.71"), l.most
  end

  test "the worked example with 3 of the 4 art hours being Lapse coding" do
    l = lapse_limits(10, ai: 3, art: 4, lapse: 3, coding: 3)
    assert_equal 1, l.art, "only the designing hour stays art"
    assert_equal 9, l.coding
    assert_equal 7, l.coding_cap, "9 of coding less two thirds of 3"
    assert_equal 3, l.art_max, "7 * 30 / 70"
    assert_equal 1, l.art_allowed
    assert_equal 8, l.most, "7 of coding and the 1 hour of art"
    assert_not l.reason&.include?("art"), "art is under the cap, so it cuts nothing"
  end

  test "the rest of the Lapse hours and designing time still share the cap" do
    l = lapse_limits(10, art: 6, lapse: 5, coding: 2)
    assert_equal 4, l.art, "4 of art left: 1 Lapse hour and 1 + 2 designing... 6 less 2"
    assert_equal 6, l.coding
    assert_equal BigDecimal("2.57"), l.art_allowed.floor(2), "6 * 30 / 70"
    assert_equal BigDecimal("8.57"), l.most
    assert_match "not counting the Lapse coding", l.reason
  end

  test "Lapse coding is held between 0 and the Lapse hours, and nothing moves when Lapse time is unknown" do
    assert_equal 3, lapse_limits(10, art: 4, lapse: 3, coding: 9).lapse_coding
    assert_equal 0, lapse_limits(10, art: 4, lapse: 3, coding: -1).lapse_coding
    unknown = Ship::Limits.new(claimed: 10, ai_coding_seconds: 0, art_seconds: 4 * 3600, lapse_seconds: nil, lapse_coding_hours: 2)
    assert_equal 0, unknown.lapse_coding
    assert_equal 4, unknown.art
    assert_not unknown.lapse_known?
  end

  test "hours print without a trailing zero" do
    assert_equal "4", Ship::Limits.format(4)
    assert_equal "5.71", Ship::Limits.format(BigDecimal("5.714"))
    assert_equal "0.5", Ship::Limits.format(0.5)
  end

  test "an amount under a hundredth keeps two digits, so a cut that small still reads as one (D-111)" do
    assert_equal "0.0067", Ship::Limits.format(BigDecimal("0.00666667"))
    assert_equal "0.00028", Ship::Limits.format(BigDecimal("0.000277778"))
    assert_equal "0.01", Ship::Limits.format(BigDecimal("0.01"))
    assert_equal "0", Ship::Limits.format(0)
    assert_equal "0.0067 hrs", Ship::Limits.hrs(BigDecimal("0.00666667"))
  end

  # D-111: a ship that was approved at 5.29 hours with no reason. 5.3 counted, no AI coding, 5542 s of art (1.539444 hrs). Coding 3.760556 and art 1.539444 each
  # round down on their own to 3.76 and 1.53, which make 5.29, a hundredth under the 5.30 the rules allow, with no reason.
  test "approving the most the rules allow stores exactly the most, not a hundredth under (D-111)" do
    l = limits(BigDecimal("5.3"), art: 5542.0 / 3600)
    assert_equal BigDecimal("5.3"), l.most
    assert_equal BigDecimal("3.76"), l.coding_top
    assert_equal BigDecimal("1.54"), l.art_top(l.coding_top), "the hundredth the floors lose goes to art: its remainder (0.0094) is the larger"
    assert_equal [ BigDecimal("3.76"), BigDecimal("1.54"), false ], l.approve(nil, nil)
    assert_equal l.approve(nil, nil), l.approve(BigDecimal("3.76"), BigDecimal("1.54")), "the form's defaults are the same figures"
    assert_not l.cut?
    assert_nil l.reason
  end

  test "the hundredth the floors lose goes to the part that lost the larger share of one" do
    # coding 3.765 and art 1.535 leave remainders 0.005 and 0.005, a tie that coding takes
    tie = limits(BigDecimal("5.3"), art: BigDecimal("1.535"))
    assert_equal BigDecimal("5.3"), tie.most
    assert_equal BigDecimal("3.77"), tie.coding_top
    assert_equal BigDecimal("1.53"), tie.art_top(tie.coding_top)
    # coding 3.7690 and art 1.5310: coding lost 0.009, art 0.001
    coding_larger = limits(BigDecimal("5.3"), art: BigDecimal("1.531"))
    assert_equal BigDecimal("3.77"), coding_larger.coding_top
    assert_equal BigDecimal("1.53"), coding_larger.art_top(coding_larger.coding_top)
  end

  test "below the top coding the art top is the art hold on that coding, rounded down" do
    l = limits(BigDecimal("5.3"), art: 5542.0 / 3600)
    assert_equal [ BigDecimal("3.74"), BigDecimal("1.53"), true ], l.approve(BigDecimal("3.74"), nil), "the art claimed is 1.5394, rounded down"
    assert_equal [ BigDecimal("3.76"), BigDecimal("1.5"), true ], l.approve(nil, BigDecimal("1.5"))
    assert_equal [ BigDecimal("3.76"), BigDecimal("1.54"), false ], l.approve(BigDecimal("3.755"), BigDecimal("1.535")), "within a rounding of the top is the top"
    assert_equal [ BigDecimal("3.74"), BigDecimal("1.53"), true ], l.approve(BigDecimal("3.74"), 9), "art typed above its top is held to it"
  end

  test "typed figures are kept to the hundredth" do
    l = limits(10, ai: 3, art: 4)
    coding, art, below = l.approve(BigDecimal("3.456"), BigDecimal("1.234"))
    assert_equal [ BigDecimal("3.46"), BigDecimal("1.23"), true ], [ coding, art, below ]
  end

  # D-111: a cut of any size lowers the stored total, so the reason names it, a few seconds of AI coding included.
  test "any cut that lowers the stored total is named in the reason, however small" do
    l = limits(BigDecimal("5.3"), ai: 36.0 / 3600)
    assert_operator l.ai_cut, :>, 0
    assert_operator l.ai_cut, :<, Ship::Limits::TOLERANCE
    assert_equal BigDecimal("5.29"), l.most, "5.3 less 0.0067 rounds down to 5.29"
    assert l.cut?
    assert_equal "Hackatime has 0.01 hrs of AI coding on this game, which counts at a third (0.0033 hrs).", l.reason
    art = limits(BigDecimal("5.3"), art: 5.3 * 0.3 + 0.001)
    assert_operator art.art_cut, :>, 0
    assert art.cut?
    assert_match(/art \(designing and Lapse\)/, art.reason)
    seconds = limits(BigDecimal("5.3"), ai: 1.0 / 3600)
    assert seconds.cut?, "one second of AI coding"
    assert_match "AI coding", seconds.reason
  end

  test "nothing is named when nothing lowers the total, and the claimed hours are read to the hundredth" do
    assert_nil limits(BigDecimal("5.3"), ai: 0, art: 1).reason
    rounded = limits(BigDecimal("5.296"))
    assert_equal BigDecimal("5.3"), rounded.claimed, "the decimal(6,2) column keeps it so"
    assert_equal BigDecimal("5.3"), rounded.most
    assert_not rounded.cut?
  end

  def random_limits(rng, claimed)
    ai = rng.rand < 0.4 ? 0 : (rng.rand * claimed.to_f * 3600 * rng.rand).to_i
    art = rng.rand < 0.3 ? 0 : (rng.rand * claimed.to_f * 3600 * rng.rand).to_i
    [ Ship::Limits.new(claimed:, ai_coding_seconds: ai, art_seconds: art), ai, art ]
  end

  test "approving the most stores exactly the most, and the claimed hours when nothing is cut, for any hours" do
    rng = Random.new(111)
    cases = 4000.times.map do
      claimed = BigDecimal((rng.rand * 40).round(2).to_s)
      l, ai, art = random_limits(rng, claimed)
      coding, art_hours, below = l.approve(nil, nil)
      label = [ claimed, ai, art ].inspect
      assert_equal l.most, coding + art_hours, "the total is the most for #{label}"
      assert_equal [ coding, art_hours ], [ l.coding_top, l.art_top(l.coding_top) ], label
      assert_not below, label
      assert_equal l.claimed, coding + art_hours, "nothing is cut for #{label}" unless l.cut?
      assert_equal l.cut?, !l.reason.nil?, "a cut is named for #{label}"
      assert_equal l.ai_cut.positive?, l.reason.to_s.include?("AI coding"), label
      assert_equal l.art_cut.positive?, l.reason.to_s.include?("of art"), label
      assert_operator art_hours, :<=, l.art_allowed_for(coding) + BigDecimal("0.01"), "art passes its hold by at most a hundredth for #{label}"
      assert_operator coding, :<=, l.coding_cap + BigDecimal("0.01"), label
      l.cut?
    end
    assert_includes cases, true
    assert_includes cases, false
  end

  # D-097, D-111: a later ship's review judges the new hours. Approving the most there reaches the most on the whole project,
  # whether the earlier approval was stored by this rounding or by the floors an earlier build used.
  test "a later ship approving the most reaches the most on the whole project, however the earlier approval was rounded" do
    rng = Random.new(97)
    checked = 0
    3000.times do
      claimed = BigDecimal((rng.rand * 30).round(2).to_s)
      first, ai, art = random_limits(rng, claimed)
      later_claimed = claimed + BigDecimal((rng.rand * 20).round(2).to_s)
      later_ai = ai + (rng.rand < 0.5 ? 0 : (rng.rand * (later_claimed - claimed) * 3600 * rng.rand).to_i)
      later_art = art + (rng.rand < 0.4 ? 0 : (rng.rand * (later_claimed - claimed) * 3600 * rng.rand).to_i)
      later = Ship::Limits.new(claimed: later_claimed, ai_coding_seconds: later_ai, art_seconds: later_art)
      old_coding = first.coding_cap.floor(2)
      [ [ first.coding_top, first.art_top(first.coding_top) ], [ old_coding, first.art_allowed_for(old_coding).floor(2) ] ].each do |earlier_coding, earlier_art|
        next if later.most < earlier_coding + earlier_art

        coding, art_hours, below = later.approve_new(earlier_coding, earlier_art, nil, nil)
        label = [ claimed, ai, art, later_claimed, later_ai, later_art, earlier_coding, earlier_art ].inspect
        assert_equal later.most, earlier_coding + earlier_art + coding + art_hours, label
        assert_not below, label
        checked += 1
      end
    end
    assert_operator checked, :>, 3000
  end
end
