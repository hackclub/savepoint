require "test_helper"

class NpsResponseTest < ActiveSupport::TestCase
  setup do
    NpsResponse.asking = true
    @user = users(:orpheus)
    @admins = Rails.configuration.x.admin_slack_ids
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  def answer(user = @user, at: Time.current, **attributes)
    NpsResponse.create!({ user:, source: "daily", score: 8, doing_well: "The streak", improve: "More prizes", created_at: at }.merge(attributes))
  end

  test "a score from 0 to 10 and the two required answers" do
    assert NpsResponse.new(user: @user, source: "daily", score: 0, doing_well: "a", improve: "b").valid?
    assert_not NpsResponse.new(user: @user, source: "daily", score: 11, doing_well: "a", improve: "b").valid?
    assert_not NpsResponse.new(user: @user, source: "daily", score: 5, doing_well: " ", improve: "b").valid?
    assert_not NpsResponse.new(user: @user, source: "daily", score: 5, doing_well: "a", improve: "").valid?
    assert NpsResponse.new(user: @user, source: "daily", score: 5, doing_well: "a", improve: "b", anything_else: nil).valid?
  end

  test "a ship answer needs its project" do
    assert_not NpsResponse.new(user: @user, source: "ship", score: 5, doing_well: "a", improve: "b").valid?
    assert NpsResponse.new(user: @user, project: @user.project, source: "ship", score: 5, doing_well: "a", improve: "b").valid?
  end

  test "due until an answer from the last 12 hours" do
    assert NpsResponse.due?(@user)
    answer(at: 13.hours.ago)
    assert NpsResponse.due?(@user)
    answer(at: 11.hours.ago)
    assert_not NpsResponse.due?(@user)
    assert NpsResponse.due?(@user, now: 2.hours.from_now)
  end

  test "an admin on the list is never asked, and nobody is while asking is off" do
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    assert_not NpsResponse.due?(@user)
    Rails.configuration.x.admin_slack_ids = []
    NpsResponse.asking = false
    assert_not NpsResponse.due?(@user)
    assert_not NpsResponse.participant?(nil)
  end

  test "the popup waits for some Hackatime time" do
    assert_not NpsResponse.ask?(@user)
    @user.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 120)
    assert NpsResponse.ask?(@user)
    answer
    assert_not NpsResponse.ask?(@user)
  end
end
