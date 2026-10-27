require "test_helper"

# A read of an FAQ question (D-094): the key, whole seconds and the time, and nothing about a person.
class FaqReadTest < ActiveSupport::TestCase
  KEY = "shipping.what-does-my-repository-need".freeze
  OTHER = "prizes.can-i-get-more-than-one-prize".freeze
  ANA = "3f2b8c1e-5a4d-4e7f-9b6a-1c2d3e4f5a6b".freeze
  BEN = "9a8b7c6d-1e2f-4a3b-8c4d-5e6f7a8b9c0d".freeze

  test "a known question's read is kept with its seconds" do
    read = FaqRead.record(KEY, "12")

    assert read.persisted?
    assert_equal [ KEY, 12 ], [ read.key, read.seconds ]
    assert_not_nil read.created_at
  end

  test "the table holds no column that names a person, only the browser's random reader ID" do
    assert_equal %w[created_at id key reader_id seconds], FaqRead.column_names.sort
  end

  test "a UUID-shaped reader ID is kept" do
    assert_equal ANA, FaqRead.record(KEY, 5, ANA).reader_id
    assert_equal ANA, FaqRead.record(KEY, 5, ANA.upcase).reader_id
  end

  test "no reader ID, as an older page sends it, keeps the read with none" do
    assert_nil FaqRead.record(KEY, 5).reader_id
    assert_nil FaqRead.record(KEY, 5, "").reader_id
  end

  test "a malformed reader ID is left off and the read is kept" do
    [ "not-a-uuid", "3f2b8c1e-5a4d-4e7f-9b6a-1c2d3e4f5a6", "#{ANA}-extra", "a" * 65, "<script>", ANA.tr("-", "") ].each do |bad|
      read = FaqRead.record(KEY, 5, bad)
      assert read.persisted?, "#{bad.inspect} should still keep the read"
      assert_nil read.reader_id
    end
  end

  test "the model refuses a malformed reader ID" do
    assert_not FaqRead.new(key: KEY, seconds: 5, reader_id: "nope").valid?
    assert FaqRead.new(key: KEY, seconds: 5, reader_id: nil).valid?
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

  test "stats list every question, most people first, then most opens, with the average per person" do
    FaqRead.record(KEY, 10, ANA)
    FaqRead.record(KEY, 30, ANA)
    FaqRead.record(KEY, 20, BEN)
    FaqRead.record(OTHER, 60, ANA)
    FaqRead.record(OTHER, 60, ANA)
    FaqRead.record(OTHER, 60, ANA)

    rows = FaqStats.new.rows
    assert_equal Faq.keys.size, rows.size
    assert_equal [ KEY, OTHER ], rows.first(2).map(&:key)
    assert_equal [ 2, 3, 30.0, 1.0 ], rows.first.then { [ it.people, it.opens, it.average_seconds, it.total_minutes ] }
    assert_equal [ 1, 3, 180.0, 3.0 ], rows.second.then { [ it.people, it.opens, it.average_seconds, it.total_minutes ] }
    assert_equal [ 0, 0, nil ], rows.last.then { [ it.people, it.opens, it.average_seconds ] }
  end

  test "reads from before the reader ID count as opens and minutes, never as people" do
    FaqRead.record(KEY, 60)
    FaqRead.record(KEY, 60)
    FaqRead.record(KEY, 30, ANA)

    row = FaqStats.new.rows.find { it.key == KEY }
    assert_equal [ 1, 3, 30.0, 2.5 ], [ row.people, row.opens, row.average_seconds, row.total_minutes ]
  end

  test "a question with only older reads has opens but no people or average" do
    FaqRead.record(OTHER, 60)

    row = FaqStats.new.rows.find { it.key == OTHER }
    assert_equal [ 0, 1, nil ], [ row.people, row.opens, row.average_seconds ]
  end
end
