require "test_helper"

class ExtensionTest < ActiveSupport::TestCase
  test "asking needs a reason, and only once per project" do
    extension = projects(:orpheus).build_extension(reason: "  ")
    assert_not extension.valid?
    assert_equal [ "Reason is needed: a line on why" ], extension.errors.full_messages

    extension.reason = "x" * (Extension::REASON_MAX + 1)
    assert_not extension.valid?

    extension.reason = " exams this week "
    assert extension.save
    assert_equal "exams this week", extension.reason
    assert extension.pending?

    again = Extension.new(project: projects(:orpheus), reason: "and next week")
    assert_not again.valid?
    assert_equal [ "Project has asked already" ], again.errors.full_messages
    assert_raises(ActiveRecord::RecordNotUnique) { again.save(validate: false) }
  end

  test "an admin decides once" do
    extension = projects(:ana).create_extension!(reason: "exams")
    assert_not extension.decide!("maybe", by: users(:orpheus))
    assert extension.pending?

    travel_to Time.utc(2026, 11, 4, 15) do
      assert extension.decide!("approved", by: users(:orpheus))
    end
    assert extension.approved?
    assert_equal users(:orpheus), extension.decided_by
    assert_equal Time.utc(2026, 11, 4, 15), extension.decided_at

    assert_not extension.decide!("denied", by: users(:orpheus))
    assert extension.reload.approved?
  end
end
