require "test_helper"

class CodedBucketTest < ActiveSupport::TestCase
  setup { @user = users(:orpheus) }

  def span(at, minutes) = { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f }

  test "a span is cut into 5-minute pieces" do
    now = Time.utc(2026, 10, 26, 12)
    CodedBucket.rewrite_for(@user, [ span(Time.utc(2026, 10, 26, 10, 3), 9) ], held: false, now:)

    pieces = @user.coded_buckets.order(:bucket_at).pluck(:bucket_at, :seconds)
    assert_equal [ [ Time.utc(2026, 10, 26, 10, 0), 120 ], [ Time.utc(2026, 10, 26, 10, 5), 300 ], [ Time.utc(2026, 10, 26, 10, 10), 120 ] ], pieces
  end

  test "a rewrite replaces the recent pieces, keeps none of the very old, and holds time for an unconfirmed link" do
    now = Time.utc(2026, 10, 26, 12)
    CodedBucket.create!(user: @user, bucket_at: Time.utc(2026, 10, 26, 9), seconds: 99)
    CodedBucket.create!(user: @user, bucket_at: Time.utc(2026, 10, 20, 9), seconds: 99)
    CodedBucket.rewrite_for(@user, [ span(Time.utc(2026, 10, 26, 10), 5) ], held: true, now:)

    assert_equal [ [ 0, 300 ] ], @user.coded_buckets.pluck(:seconds, :unconfirmed_seconds)
    CodedBucket.release_held!(@user)
    assert_equal [ [ 300, 0 ] ], @user.coded_buckets.pluck(:seconds, :unconfirmed_seconds)
  end
end
