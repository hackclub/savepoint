require "test_helper"

# A read of an FAQ question (D-094): the key, whole seconds and the time, and nothing about a person.
class FaqReadTest < ActiveSupport::TestCase
  KEY = "shipping.what-does-my-repository-need".freeze

  test "a known question's read is kept with its seconds" do
    read = FaqRead.record(KEY, "12")

    assert read.persisted?
    assert_equal [ KEY, 12 ], [ read.key, read.seconds ]
    assert_not_nil read.created_at
  end

  test "the table holds no column that names a person" do
    assert_equal %w[created_at id key seconds], FaqRead.column_names.sort
  end

  test "an unknown key is dropped" do
    assert_no_difference("FaqRead.count") { assert_nil FaqRead.record("shipping.nope", 5) }
  end

  test "under a second, or not a whole number, is dropped" do
    [ 0, -3, "0", "abc", "1.5", nil ].each do |seconds|
      assert_nil FaqRead.record(KEY, seconds), "#{seconds.inspect} should be dropped"
    end
    assert_equal 0, FaqRead.count
  end

  test "a read over ten minutes is cut to ten minutes" do
    assert_equal 600, FaqRead.record(KEY, 5_000).seconds
  end

  test "the page gives every question a unique key, led by its group's anchor" do
    keys = Faq.keys
    assert_equal keys.uniq, keys
    assert_equal %w[basics hours how-to-ship shipping prizes help], Faq.groups.map(&:slug)
    assert_includes keys, KEY
    assert Faq.groups.find { it.slug == "shipping" }.entries.all? { it.key.start_with?("shipping.") }
  end

  test "stats list every question, most opens first, with the median and total minutes" do
    other = "prizes.can-i-get-more-than-one-prize"
    FaqRead.record(KEY, 10)
    FaqRead.record(KEY, 30)
    FaqRead.record(KEY, 20)
    FaqRead.record(other, 60)

    rows = FaqStats.new.rows
    assert_equal Faq.keys.size, rows.size
    assert_equal [ KEY, other ], rows.first(2).map(&:key)
    assert_equal [ 3, 20.0, 1.0 ], rows.first.then { [ it.opens, it.median_seconds, it.total_minutes ] }
    assert_equal [ 0, nil ], rows.last.then { [ it.opens, it.median_seconds ] }
  end
end
