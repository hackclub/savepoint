require "test_helper"

class NudgeBanditTest < ActiveSupport::TestCase
  Context = Struct.new(:user, :today, :vars, :now, keyword_init: true)

  setup do
    @user = users(:orpheus)
    @context = Context.new(user: @user, today: Nudge::Bandit::EXPLORE_UNTIL, vars: {}, now: Time.current)
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

  def sent_to_orpheus!(arm, ago, kind: "bandit")
    @user.nudges.create!(kind:, bucket: "lapsed", arm:, delivered: true, sent_at: @context.now - ago)
  end

  test "an arm they were sent recently has its draw cut, by half as long ago as it's been sent" do
    sent_to_orpheus!("tiny_step", 1.minute)
    sent_to_orpheus!("pledge", 2.days)
    sent_to_orpheus!("social", 6.days)
    sent_to_orpheus!("overtake", 9.days)
    sent_to_orpheus!("progress", 1.day, kind: "cheer")
    multipliers = Nudge::Bandit.new("lapsed").recency_multipliers(@user, @context.now)

    assert_in_delta 0.5, multipliers.fetch("tiny_step"), 0.001
    assert_in_delta 0.75, multipliers.fetch("pledge"), 0.001, "one half-life on, half the penalty"
    assert_in_delta 0.9375, multipliers.fetch("social"), 0.001
    assert_not multipliers.key?("overtake"), "past the lookback"
    assert_in_delta 0.65, multipliers.fetch("progress"), 0.01
  end

  test "sends add up, and the draw never goes below zero" do
    4.times { sent_to_orpheus!("pledge", 1.minute) }
    assert_equal 0.0, Nudge::Bandit.new("lapsed").recency_multipliers(@user, @context.now).fetch("pledge")
  end

  test "of two arms the bandit rates the same, it favours the one they weren't just sent" do
    sent_to_orpheus!("tiny_step", 1.minute)
    picks = not_holdout { 300.times.map { Nudge::Bandit.new("lapsed").pick(@context) } }

    pledge = picks.select { |arm, *| arm == "pledge" }
    assert_operator pledge.size, :>, 190, "about 3 in 4 (a flat draw halved loses to a flat draw 3 times in 4)"
    assert_in_delta 0.75, pledge.sum { |_, propensity, _| propensity } / pledge.size, 0.06, "and the logged odds say so too"
  end

  test "the holdout ignores what they were sent" do
    sent_to_orpheus!("tiny_step", 1.minute)
    assert_equal [ "tiny_step", 1.0, true ], holdout(true) { Nudge::Bandit.new("lapsed").pick(@context) }
  end

  test "in the first two days, when every arm is equally likely, what they were sent doesn't matter" do
    @context.today = Nudge::Bandit::EXPLORE_UNTIL - 1
    sent_to_orpheus!("tiny_step", 1.minute)
    arms = not_holdout { 100.times.map { Nudge::Bandit.new("lapsed").pick(@context).first } }
    assert_includes arms, "tiny_step"
  end
end
