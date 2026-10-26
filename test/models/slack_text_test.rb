require "test_helper"

class SlackTextTest < ActiveSupport::TestCase
  test "escapes the three characters Slack reads as markup" do
    assert_equal "&lt;!channel&gt; &lt;https://evil.example|x&gt;", SlackText.escape("<!channel> <https://evil.example|x>")
  end

  test "escapes the ampersand first, so nothing is escaped twice" do
    assert_equal "a &amp; b &amp;lt; c", SlackText.escape("a & b &lt; c")
  end

  test "leaves bold and italics alone" do
    assert_equal "*bold* _it_ :)", SlackText.escape("*bold* _it_ :)")
  end

  test "nil is an empty string, and other values are made into text" do
    assert_equal "", SlackText.escape(nil)
    assert_equal "5", SlackText.escape(5)
  end

  test "strips control characters except the newline" do
    assert_equal "a\nb", SlackText.escape("a\u0000\u0007\u001b\n\u007fb")
  end
end
