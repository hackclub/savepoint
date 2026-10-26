require "test_helper"

class NudgeBanditTest < ActiveSupport::TestCase
  Context = Struct.new(:user, :today, :vars, keyword_init: true)

  setup do
    @user = users(:orpheus)
    @context = Context.new(user: @user, today: Nudge::Bandit::EXPLORE_UNTIL, vars: {})
  end

  def scored!(arm, reward, count, bucket: "lapsed")
    count.times { users(:ana).nudges.create!(kind: "bandit", bucket:, arm:, reward:, delivered: true, sent_at: 1.day.ago) }
  end

  def holdout(value)
    original = Nudge::Bandit.method(:holdout?)
    Nudge::Bandit.define_singleton_method(:holdout?) { |_| value }
    yield
  ensure
    Nudge::Bandit.define_singleton_method(:holdout?, original)
  end

  def not_holdout(&) = holdout(false, &)

  test "it leans towards the arm that gets people building, while still trying the others" do
    scored!("tiny_step", 1, 12)
    scored!("tiny_step", 0, 3)
    %w[social pledge].each { |arm| scored!(arm, 0, 15) }

    arm, propensity, holdout = not_holdout { Nudge::Bandit.new("lapsed").pick(@context) }

    assert_equal "tiny_step", arm
    assert_operator propensity, :>, 0.9
    assert_not holdout
  end

  test "stopping the bot's messages counts as several failures" do
    scored!("social", Nudge::OPT_OUT_PENALTY, 1)
    assert_equal({ successes: 0, failures: Nudge::OPT_OUT_PENALTY.abs }, Nudge::Bandit.new("lapsed").results(Nudge.all))
  end

  test "a bucket borrows a little from how an arm does everywhere else" do
    scored!("progress", 1, 10, bucket: "on_pace")
    a, b = Nudge::Bandit.new("behind").posterior("progress")
    assert_in_delta 1 + 10 * Nudge::Bandit::POOLED_WEIGHT, a
    assert_equal 1, b
  end

  test "at first every arm is equally likely" do
    @context.today = Nudge::Bandit::EXPLORE_UNTIL - 1
    arm, propensity, = not_holdout { Nudge::Bandit.new("lapsed").pick(@context) }

    assert_includes %w[tiny_step pledge], arm
    assert_in_delta 1 / 2.0, propensity, 0.001, "social needs peers, so it's out"
  end

  test "the holdout always gets the same best guess, so we can tell if the bandit helps" do
    arm, propensity, holdout = holdout(true) { Nudge::Bandit.new("lapsed").pick(@context) }
    assert_equal [ "tiny_step", 1.0, true ], [ arm, propensity, holdout ]
  end

  test "about a tenth of people are in the holdout, the same ones every time" do
    share = (1..2000).count { |id| Nudge::Bandit.holdout?(User.new(id:)) } / 2000.0
    assert_in_delta Nudge::Bandit::HOLDOUT_SHARE, share, 0.03
  end
end
