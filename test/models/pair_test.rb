require "test_helper"

class PairTest < ActiveSupport::TestCase
  test "two projects pair once, and each is the other's buddy" do
    pair = projects(:orpheus).pair_with(projects(:ana))

    assert pair.persisted?
    assert_equal projects(:ana), projects(:orpheus).reload.buddy
    assert_equal projects(:orpheus), projects(:ana).reload.buddy
    assert projects(:orpheus).step_done?("buddy")
    assert_not projects(:orpheus).step_open?("buddy")

    again = projects(:ana).pair_with(projects(:orpheus))
    assert_not again.persisted?
    assert_equal [ "One of you already has a buddy" ], again.errors.full_messages
  end

  test "you can't pair with yourself" do
    assert_equal [ "You can't pair with yourself" ], projects(:ana).pair_with(projects(:ana)).errors.full_messages
  end

  test "an invite code is random, so the link says nothing about who sent it, and it stays the same" do
    code = projects(:orpheus).buddy_code!

    assert_match(/\A[a-z0-9]{8}\z/, code)
    assert_no_match(/orph/i, code)
    assert_equal code, projects(:orpheus).reload.buddy_code!
    assert_equal "k3j9x2qa", projects(:ana).buddy_code!
  end
end
