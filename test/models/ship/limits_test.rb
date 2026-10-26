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
end
