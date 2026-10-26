require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include LandingHelper # name_with_slack draws its icon with sp_icon
  include InlineSvg::ActionView::Helpers

  test "a name links to their Slack profile in a new tab when they have a Slack ID, with an icon as the cue" do
    ana = users(:ana)
    ana.slack_display_name = "pixel ana"
    ana.slack_id = "U0ANA"
    link = Nokogiri::HTML.fragment(name_with_slack(ana, class: "x", tabindex: -1)).at_css("a")
    assert_equal "https://hackclub.slack.com/team/U0ANA", link["href"]
    assert_equal "_blank", link["target"]
    assert_equal "noopener noreferrer", link["rel"]
    assert_equal "pixel ana's Slack profile (opens in a new tab)", link["aria-label"]
    assert_equal "slack-name x", link["class"]
    assert_equal "-1", link["tabindex"]
    assert_equal "pixel ana", link.text.strip
    assert_equal "ana", link.at_css(".slack-name__end").text.strip, "the last word and the icon stay together"
    assert link.at_css(".slack-name__end svg"), "the external-link icon follows the name"
    assert_equal "pixel ana", Nokogiri::HTML.fragment(name_with_slack(ana, name: "pixel ana")).at_css("a").text.strip
  end

  test "a name with no Slack ID is plain text, with no link and no icon" do
    ana = users(:ana)
    ana.slack_display_name = "pixel ana"
    ana.slack_id = nil
    assert_equal "pixel ana", name_with_slack(ana)
  end

  test "someone's picture is their Slack one, or else the first letter of their public name" do
    ana = users(:ana)
    ana.slack_display_name = "pixel ana"
    ana.slack_avatar_url = "https://avatars.slack-edge.com/ana_512.png"
    picture = Nokogiri::HTML.fragment(avatar_tag(ana, "leaderboard__avatar")).at_css("span.avatar")
    assert_equal "pixel ana", picture["aria-label"]
    image = picture.at_css("img")
    assert_equal "https://avatars.slack-edge.com/ana_512.png", image["src"]
    assert_equal "", image["alt"]
    assert_equal "lazy", image["loading"]
    assert_equal "no-referrer", image["referrerpolicy"]
    assert_nil picture.at_css(".avatar__initial")

    ana.slack_avatar_url = nil
    plain = Nokogiri::HTML.fragment(avatar_tag(ana)).at_css("span.avatar")
    assert_nil plain.at_css("img")
    assert_equal "P", plain.at_css(".avatar__initial")["data-initial"]
    assert_nil plain.at_css("svg")

    ana.slack_display_name = nil
    ana.slack_username = nil
    assert_equal ana.public_name.first, Nokogiri::HTML.fragment(avatar_tag(ana)).at_css(".avatar__initial")["data-initial"]
  end
end
