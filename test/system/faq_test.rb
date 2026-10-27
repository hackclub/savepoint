require "application_system_test_case"

# The landing FAQ (D-093, D-094): a hash opens a question, one question is open at a time, and the time a question stays open is recorded.
class FaqTest < ApplicationSystemTestCase
  FIRST = "basics.does-my-game-need-to-be-from-a-game-jam".freeze
  SECOND = "basics.can-i-start-a-new-game".freeze

  test "opening a question closes the one that was open, and its read time is recorded" do
    visit root_path
    find("details[id='#{FIRST}'] summary").click
    assert_selector "details[id='#{FIRST}'][open]"

    find("details[id='#{SECOND}'] summary").click
    assert_selector "details[id='#{SECOND}'][open]"
    assert_no_selector "details[id='#{FIRST}'][open]"
    assert_selector "details[open]", count: 1

    # A read under a second isn't kept, so the first question left no read.
    assert_equal 0, FaqRead.where(key: FIRST).count

    sleep 1.2
    find("details[id='#{SECOND}'] summary").click
    assert_no_selector "details[open]"
    assert_equal 1, wait_for_reads(SECOND)
    assert_operator FaqRead.find_by(key: SECOND).seconds, :>=, 1
    # The beacon carries the browser's random reader ID (D-095), which the page keeps in localStorage.
    reader_id = FaqRead.find_by(key: SECOND).reader_id
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, reader_id)
    assert_equal reader_id, evaluate_script("localStorage.getItem('sp_faq_reader')")
  end

  test "a group's anchor scrolls to it, and a question's key or the old position opens it" do
    visit "#{root_path}#shipping"
    assert_selector "#shipping h3", text: "WHAT COUNTS AS A SHIPPED PROJECT?"
    # The page scrolls smoothly, so the group is on screen once the scroll ends.
    Timeout.timeout(5) { sleep 0.1 until evaluate_script("document.querySelector('#shipping').getBoundingClientRect().top").between?(0, 400) }

    visit "#{root_path}#shipping.what-does-my-repository-need"
    assert_selector "details[open]", count: 1
    assert_selector "details[id='shipping.what-does-my-repository-need'][open]"

    visit "#{root_path}#faq-2"
    assert_selector "details[id='#{SECOND}'][open]"
  end

  private
    def wait_for_reads(key)
      Timeout.timeout(5) { sleep 0.1 until FaqRead.where(key:).exists? }
      FaqRead.where(key:).count
    end
end
