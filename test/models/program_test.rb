require "test_helper"

class ProgramTest < ActiveSupport::TestCase
  test "before the start there is no day, and the label says it starts soon" do
    travel_to Program::STARTS_AT - 1.second do
      assert_nil Program.day
      assert_equal "Starts soon", Program.day_label
    end
  end

  test "the first day starts at STARTS_AT" do
    travel_to Program::STARTS_AT do
      assert_equal({ number: 1, total: 10 }, Program.day)
      assert_equal "Day 1 of 10", Program.day_label
    end
  end

  test "the middle counts 24-hour days" do
    travel_to Program::STARTS_AT + 4.days + 5.hours do
      assert_equal "Day 5 of 10", Program.day_label
    end
  end

  test "the last day lasts until ENDS_AT" do
    travel_to Program::ENDS_AT - 1.second do
      assert_equal "Day 10 of 10", Program.day_label
    end
  end

  test "after the end it still shows the last day" do
    travel_to Program::ENDS_AT + 30.days do
      assert_equal "Day 10 of 10", Program.day_label
    end
  end

  test "PROGRAM_STARTS_AT sets the start when it is a valid ISO 8601 time" do
    assert_equal Time.utc(2026, 10, 23, 1, 30), Program.starts_at_from("2026-10-23T01:30:00Z")
    assert_equal Time.utc(2026, 10, 22, 23), Program.starts_at_from(" 2026-10-23T01:00:00+02:00 ")
  end

  test "an absent or invalid PROGRAM_STARTS_AT falls back to the default start" do
    [ nil, "", "  ", "soon", "2026-10-23", "2026-13-40T00:00:00Z", "10/23/2026" ].each do |value|
      assert_equal Program::DEFAULT_STARTS_AT, Program.starts_at_from(value), value.inspect
    end
    assert_equal Time.utc(2026, 10, 23, 21), Program::DEFAULT_STARTS_AT
  end

  test "with a 01:30 UTC start the program has 11 days and the last one is stretched to the end" do
    out = ruby_with_start("2026-10-23T01:30:00Z", <<~RUBY)
      puts [ Program::STARTS_AT.iso8601, Program::DATES.to_s, Program::HACKATIME_START,
             Program.day(Time.utc(2026, 10, 23, 1, 29)).inspect, Program.day_label(Time.utc(2026, 10, 23, 1, 30)),
             Program.day_label(Time.utc(2026, 10, 24, 1, 29)), Program.day_label(Time.utc(2026, 10, 24, 1, 30)),
             Program.day_label(Time.utc(2026, 11, 2, 20, 59)), Program.day_label(Time.utc(2026, 12, 1)),
             Program.today(Time.utc(2026, 10, 23, 1, 30)), Program.today(Time.utc(2026, 10, 24, 5)),
             Program.today(Time.utc(2026, 11, 2, 20, 59)), Prize.pace_minutes(11, from: Time.utc(2026, 10, 23, 1, 30)) ]
    RUBY
    assert_equal [ "2026-10-23T01:30:00Z", "2026-10-23..2026-11-02", "2026-10-23", "nil", "Day 1 of 11", "Day 1 of 11",
                   "Day 2 of 11", "Day 11 of 11", "Day 11 of 11", "2026-10-23", "2026-10-24", "2026-11-02", "65" ], out.lines.map(&:strip)
  end

  test "a start already in the past makes the program run at once" do
    out = ruby_with_start("2026-10-22T08:00:00Z", <<~RUBY)
      travel_to = Time.utc(2026, 10, 22, 12)
      puts Program.day_label(travel_to), Program.today(travel_to), Program::DATES.begin
    RUBY
    assert_equal [ "Day 1 of 12", "2026-10-22", "2026-10-22" ], out.lines.map(&:strip)
  end

  test "a leftover under half a day stretches the last day instead of adding a sliver" do
    out = ruby_with_start("2026-10-23T20:30:00Z", "puts Program.day(Program::ENDS_AT - 1).inspect")
    assert_equal "{number: 10, total: 10}", out.strip
  end

  test "the last third starts a third of the program back from the end, on Oct 30" do
    assert_equal Time.utc(2026, 10, 30, 13), Program::GOAL_SALIENCE_STARTS_AT
    assert_not Program.goal_salient?(Time.utc(2026, 10, 30, 12, 59))
    assert Program.goal_salient?(Time.utc(2026, 10, 30, 13))
    assert Program.goal_salient?(Program::ENDS_AT + 1.hour)
  end

  private

  # Constants are read when the app loads, so a start from the environment needs a fresh process.
  def ruby_with_start(value, code)
    out = IO.popen({ "PROGRAM_STARTS_AT" => value }, [ "bin/rails", "runner", code ], err: File::NULL, &:read)
    assert $?.success?, "runner failed"
    out
  end
end
