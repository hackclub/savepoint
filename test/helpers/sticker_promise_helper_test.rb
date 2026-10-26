require "test_helper"

# The free stickers' card on the project page (D-051). Fixtures are stamped at the real clock, so every test pins created_at.
class StickerPromiseHelperTest < ActionView::TestCase
  setup do
    @user = users(:orpheus)
    @user.update_column(:created_at, Time.utc(2026, 10, 25, 10))
    @spans = Hackatime.stubbed_spans
    @progress_cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Hackatime.stubbed_spans = @spans }

  def sticker_progress_cache = @progress_cache

  def track(project_names = [ "rhythm-game" ])
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: project_names)
    @user.reload
  end

  def sticker_state_at(offset)
    travel_to(@user.created_at + offset) { sticker_promise_state(@user.reload) }
  end

  test "counting with progress: minutes on the linked project inside the hour, to the deadline" do
    track
    Hackatime.stubbed_spans = { @user.hackatime_uid => [ hackatime_span(@user.created_at + 10.minutes, 3) ] }

    state = sticker_state_at(20.minutes)
    assert_equal :counting, state[:kind]
    assert_equal @user.created_at + 1.hour, state[:deadline]
    assert_equal [ true, 180, 3, 60 ], [ state[:tracking], state[:seconds], state[:minutes], state[:percent] ]
    assert_equal "3 of 5 minutes", sticker_progress_text(state)
  end

  test "the progress is kept for a couple of minutes, so a page load does not always ask Hackatime" do
    track
    Hackatime.stubbed_spans = { @user.hackatime_uid => [ hackatime_span(@user.created_at + 10.minutes, 1) ] }
    assert_equal 1, sticker_state_at(20.minutes)[:minutes]

    Hackatime.stubbed_spans = { @user.hackatime_uid => [ hackatime_span(@user.created_at + 10.minutes, 4) ] }
    assert_equal 1, sticker_state_at(20.minutes)[:minutes], "the old figure, from the cache"
  end

  test "counting without a linked Hackatime project has no progress, and says so" do
    state = sticker_state_at(5.minutes)
    assert_equal :counting, state[:kind]
    assert_equal [ false, nil ], [ state[:tracking], state[:seconds] ]
    assert_not state.key?(:minutes)
  end

  test "counting when Hackatime fails leaves the progress out" do
    track
    Hackatime.stubbed_spans = Class.new(Hash) { def fetch(*) = raise(Hackatime::Unavailable) }.new

    state = sticker_state_at(5.minutes)
    assert_equal :counting, state[:kind]
    assert_nil state[:seconds]
    assert_not state.key?(:percent)
  end

  test "earned and not claimed" do
    @user.rewards.create!(key: "stickers")
    assert_equal({ kind: :earned }, sticker_state_at(2.hours))
  end

  test "claimed" do
    @user.rewards.create!(key: "stickers")
    @user.update!(address: HQ_ADDRESS)
    @user.project.orders.create!(prize_key: "stickers")
    assert_equal({ kind: :claimed }, sticker_state_at(2.hours))
  end

  test "an account made before the stickers began has no card" do
    @user.update_column(:created_at, Reward::STICKERS_SINCE - 1.minute)
    assert_nil sticker_state_at(5.minutes)
  end

  test "once the hour has passed without earning them there is no card" do
    track
    Hackatime.stubbed_spans = { @user.hackatime_uid => [] }
    assert_nil sticker_state_at(61.minutes)
  end

  test "nobody signed in, or with no project, has no card" do
    assert_nil sticker_promise_state(nil)
    @user.project.destroy!
    assert_nil sticker_state_at(5.minutes)
  end

  test "no card for an account that is ineligible or banned by Hackatime" do
    track
    assert_equal :counting, sticker_state_at(20.minutes)[:kind]

    @user.update_columns(ysws_eligible: false)
    assert_nil sticker_state_at(20.minutes)

    @user.update_columns(ysws_eligible: true, hackatime_trust_level: "red")
    assert_nil sticker_state_at(20.minutes)

    @user.update_columns(hackatime_trust_level: "yellow")
    assert_equal :counting, sticker_state_at(20.minutes)[:kind]
    assert_nil sticker_promise_json(nil)
  end
end
