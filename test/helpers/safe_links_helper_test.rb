require "test_helper"

class SafeLinksHelperTest < ActionView::TestCase
  UNSAFE = [ "javascript:alert(1)", "JaVaScRiPt:alert(1)", "data:text/html,<script>alert(1)</script>", "vbscript:x", "file:///etc/passwd",
             "//evil.example/x", "/relative", "https://", "not a url", "" ].freeze

  test "only absolute http and https URLs are safe" do
    assert safe_http_url?("https://github.com/a/b")
    assert safe_http_url?(" http://example.com:3000/x?y=1#z ")
    UNSAFE.each { |url| assert_not safe_http_url?(url), url }
    assert_not safe_http_url?(nil)
  end

  test "a safe URL becomes a link" do
    assert_dom_equal '<a target="_blank" rel="noopener" href="https://github.com/a/b">repo</a>',
                     safe_link_to("repo", "https://github.com/a/b", target: "_blank", rel: "noopener")
    html = safe_link_to("https://example.com/s.png", target: "_blank") { "pic" }
    assert_dom_equal '<a target="_blank" href="https://example.com/s.png">pic</a>', html
  end

  test "a javascript: or data: URL is printed as text, never an href or src" do
    UNSAFE.each do |url|
      assert_equal ERB::Util.html_escape(url), ERB::Util.html_escape(safe_link_to(url, url, target: "_blank")), url
      assert_no_match(/<a /, safe_link_to(url, url).to_s)
      assert_nil safe_link_to(url) { "pic" }
      assert_nil safe_image_tag(url, alt: "x")
    end
    assert_includes safe_image_tag("https://example.com/s.png", alt: "x"), 'src="https://example.com/s.png"'
  end
end
