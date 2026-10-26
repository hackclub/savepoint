require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home is Save Point's landing page, on its own style sheet" do
    get root_path

    assert_response :success
    assert_select "title", "Save Point"
    assert_select "link[rel=stylesheet][href*='save_point/tokens']"
    assert_select "link[rel=stylesheet][href*='save_point/landing']"
    assert_select "link[rel=stylesheet][href*='foundation/']", 0
    assert_select "h1", /Finish that game you started/
  end

  test "home has a link preview with an absolute image URL" do
    get root_path

    assert_select "meta[property='og:image'][content='http://www.example.com/og-image-v4.png']"
    assert_select "meta[property='og:title'][content='Save Point']"
    assert_select "meta[property='og:url'][content='http://www.example.com/']"
    assert_select "meta[property='og:description'][content*='Finish the game you started']"
    assert_select "meta[name=description][content*='Finish the game you started']"
    assert_select "meta[name='twitter:card'][content=summary_large_image]"
    assert_select "meta[name='twitter:image'][content='http://www.example.com/og-image-v4.png']"
    assert_select "meta[name='twitter:title'][content='Save Point']"
    assert_select "meta[name='twitter:description'][content*='Finish the game you started']"
    assert File.exist?(Rails.public_path.join("og-image-v4.png"))
  end

  test "every call to action goes to onboarding" do
    get root_path

    assert_select "a.cta", 3
    assert_select "a.cta:not([href='#{onboarding_path}'])", 0
  end

  test "shows every prize, with its pace a day and its hours" do
    get root_path

    assert_select ".prize", Prize::ALL.size
    assert_select ".prize.is-goal", 1
    assert_select ".prize.is-goal .shop-card__name", Prize::DEFAULT_GOAL.name
    assert_select ".prize .shop-card__total", text: "17 hrs total"
    assert_select ".shop-card--common", 6
    assert_select ".shop-card--rare", 6
    assert_select ".shop-card--epic", 6
    assert_select ".shop-card__price img[src*='save_point/hours']", Prize::ALL.size
    assert_select ".reel__item", Prize::ALL.size * 4
    assert_select ".reel__item[aria-hidden=true]", Prize::ALL.size * 3
  end

  test "states the end in UTC for the browser to put in your time zone, and counts down to it" do
    get root_path

    assert_select "[data-controller=local-time][data-local-time-at-value='#{Program::ENDS_AT.iso8601}']", "Mon Nov 2, 2026, 9:00 pm (UTC)"
    assert_select ".cd[data-countdown-ends-at-value='#{Program::ENDS_AT.iso8601}']", 1
  end

  test "puts how many people are also finishing their game in the hero button, and says Continue when nobody is" do
    admins = Rails.configuration.x.admin_slack_ids

    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0ANA" ]
    get root_path
    assert_select ".signups", 0
    assert_select ".cta--join [data-signups-target=join][hidden]", 1, "nobody signed up yet"
    assert_select ".cta--join [data-signups-target=fallback]:not([hidden])", text: "Continue your game"

    Rails.configuration.x.admin_slack_ids = [ "U0ANA" ]
    get root_path
    assert_select "a.cta--join[href='#{onboarding_path}'] [data-signups-target=join]:not([hidden])", text: /\A\s*Join\s+1\s+person also finishing their game\s*\z/
    assert_select "a.cta--join[data-controller=signups][data-signups-url-value='#{signups_path}'][data-signups-count-value='1']"
    assert_select ".cta--join [data-signups-target=fallback][hidden]", 1

    Rails.configuration.x.admin_slack_ids = []
    get root_path
    assert_select "a.cta--join [data-signups-target=join]", text: /\A\s*Join\s+2\s+people also finishing their game\s*\z/
  ensure
    Rails.configuration.x.admin_slack_ids = admins
  end

  test "draws icons on the server" do
    get root_path

    assert_select "i[data-icon=play-fill] svg.sp-icon[aria-hidden=true]"
  end

  test "signed in, the landing page sends you to onboarding, or your project once you've pledged" do
    sign_in_as(mock_hack_club_auth)
    get root_path
    assert_redirected_to onboarding_path

    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get root_path
    assert_redirected_to project_path
  end

  private
    def sign_in_as(_auth)
      post "/auth/hackclub"
      follow_redirect!
    end

  test "the landing hero promises stickers for five minutes in the first hour" do
    get root_path

    assert_select ".hero .promise", text: /Work on your game for 5 minutes in your first hour\. Free stickers\./
    assert_select ".hero .promise img[src*=sticker-promise]"
    assert_select ".prizes .prize", Prize::ALL.size
    assert_select "#prize-stickers", 0
    assert_select ".reel__item", Prize::ALL.size * 4
  end
end
