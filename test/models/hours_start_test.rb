require "test_helper"

# D-065: Hackatime time counts from the later of Save Point's start and the sign-up, unless a reviewer set a start.
class HoursStartTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:orpheus)
    @project = @user.project
    link_hackatime(@user)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
  end

  teardown { Hackatime.stubbed_spans = {} }

  def span(at, minutes) = hackatime_span(at, minutes)

  test "someone who signed up after the launch counts from their sign-up" do
    @user.update_column(:created_at, Program::STARTS_AT + 2.days)

    assert_equal Program::STARTS_AT + 2.days, @project.hours_start
    assert_equal :sign_up, @project.hours_start_source
  end

  test "someone who signed up before the launch counts from the launch" do
    @user.update_column(:created_at, Program::STARTS_AT - 3.days)

    assert_equal Program::STARTS_AT, @project.hours_start
    assert_equal :launch, @project.hours_start_source
  end

  test "a reviewer's start wins over both, and may be before the sign-up" do
    @user.update_column(:created_at, Program::STARTS_AT + 2.days)
    travel_to(Program::STARTS_AT + 3.days) do
      @project.update!(hours_start_override: Program::STARTS_AT + 1.day)

      assert_equal Program::STARTS_AT + 1.day, @project.hours_start
      assert_equal :override, @project.hours_start_source
    end
  end

  test "the override can't be before Save Point began or in the future" do
    travel_to(Program::STARTS_AT + 3.days) do
      @project.hours_start_override = Program::STARTS_AT - 1.minute
      assert_not @project.valid?
      assert_match(/before Save Point began/, @project.errors[:hours_start_override].first)

      @project.hours_start_override = Time.current + 1.hour
      assert_not @project.valid?
      assert_equal [ "can't be in the future" ], @project.errors[:hours_start_override]

      @project.hours_start_override = Program::STARTS_AT
      assert @project.valid?, "the launch moment itself is fine"
    end
  end

  test "an old override isn't re-checked when something else on the project changes" do
    @project.update_column(:hours_start_override, Program::STARTS_AT - 1.day)
    assert @project.reload.update(idea: "A new idea")
  end

  test "the sync clips each span at the sign-up, keeping the later part of one across it" do
    signed_up = Program::STARTS_AT + 1.day
    @user.update_column(:created_at, signed_up)
    travel_to signed_up + 2.days do
      Hackatime.stubbed_spans = { "1001" => [ span(signed_up - 2.hours, 60), span(signed_up - 10.minutes, 30), span(signed_up + 1.hour, 45) ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal (20 + 45) * 60, @user.streak_activities.sum(:coded_seconds)
      assert_equal 1.1, @user.hours_in(Program::FIRST_STREAK_DATE..)
    end
  end

  test "ship hours follow the per-user start, and an override moves them" do
    signed_up = Program::STARTS_AT + 1.day
    @user.update_column(:created_at, signed_up)
    travel_to signed_up + 2.days do
      Hackatime.stubbed_spans = { "1001" => [ span(Program::STARTS_AT + 2.hours, 120), span(signed_up + 1.hour, 60) ] }
      StreakActivity.sync_for_user!(@user)
      ship = Ship.new(project: @project, hours: 10, created_at: Time.current)
      assert_equal 1.0, ship.counted_hours, "the two hours before sign-up don't count"

      @project.update!(hours_start_override: Program::STARTS_AT)
      StreakActivity.sync_for_user!(@user, from_start: true)
      assert_equal 3.0, ship.counted_hours, "from the launch the earlier two hours count too"
    end
  end

  test "changing the override rebuilds the user's days, clearing it does too" do
    travel_to Program::STARTS_AT + 3.days do
      @user.update_column(:streak_synced_at, Time.current)

      assert_enqueued_with(job: StreakSyncJob, args: [ @user.id ]) { @project.update!(hours_start_override: Program::STARTS_AT + 1.day) }
      assert_nil @user.reload.streak_synced_at, "the next sync starts from the first streak day"

      assert_enqueued_with(job: StreakSyncJob) { @project.update!(hours_start_override: nil) }
    end
  end
end
