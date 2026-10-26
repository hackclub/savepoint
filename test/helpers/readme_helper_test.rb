require "test_helper"

# A participant's README on the review page: its relative links and images point into the repository, and nothing in it
# loads this site or a host outside GitHub.
class ReadmeHelperTest < ActionView::TestCase
  def readme(html) = Nokogiri::HTML5.fragment(readme_html(html, repo: "pet/rock"))

  test "relative images load from the repository, GitHub images stay, and others go" do
    doc = readme(<<~HTML)
      <img src="media/logo.png" alt="logo"><img src="/admin/ships/1?take=1"><img src="https://camo.githubusercontent.com/abc">
      <img src="https://evil.example/pixel.png"><img src="//evil.example/pixel.png"><img src="http://raw.githubusercontent.com/x">
    HTML
    assert_equal [ "https://raw.githubusercontent.com/pet/rock/HEAD/media/logo.png",
                   "https://raw.githubusercontent.com/admin/ships/1?take=1",
                   "https://camo.githubusercontent.com/abc" ], doc.css("img").map { it["src"] }
  end

  test "relative links point into the repository, and links to this site or to scripts lose their href" do
    doc = readme(<<~HTML)
      <a href="docs/setup.md">setup</a><a href="#install">install</a><a href="https://#{request.host}/admin/review?reset=1">here</a>
      <a href="javascript:alert(1)">x</a><a href="https://example.com/">site</a>
    HTML
    assert_equal [ "https://github.com/pet/rock/blob/HEAD/docs/setup.md", "#install", nil, nil, "https://example.com/" ],
                 doc.css("a").map { it["href"] }
  end

  test "scripts and handlers are stripped, and tables survive" do
    doc = readme(%(<h1 onclick="x()">rock</h1><script>alert(1)</script><table><tr><td>a</td></tr></table><iframe src="https://evil.example"></iframe>))
    assert_equal "rock", doc.at_css("h1").text
    assert_nil doc.at_css("h1")["onclick"]
    assert_empty doc.css("script, iframe")
    assert_equal "a", doc.at_css("table td").text
  end

  test "an empty README is nothing" do
    assert_nil readme_html("", repo: "pet/rock")
  end
end
