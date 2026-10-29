require "application_system_test_case"

class OnboardingTest < ApplicationSystemTestCase
  test "the landing page's call to action opens onboarding" do
    visit root_path
    find(".hero__cta a.cta").click
    assert_current_path onboarding_path
    assert_selector "h2", text: "Which game are you building?"
  end

  test "your game, its Hackatime project and your prize, then Start building" do
    sign_in_to_hack_club
    link_hackatime(User.find_by!(hca_id: "ident!heidi"))
    visit onboarding_path

    assert_button "Next", disabled: true
    fill_in "Game name", with: "Pixel Pirates"
    fill_in "Code link", with: "not a link"
    assert_selector ".onboarding-field__hint", text: "That doesn't look like a link."
    assert_button "Next", disabled: true
    fill_in "Code link", with: "https://github.com/heidi/pirates"
    check "It was a jame gam entry."
    click_on "Next"

    assert_selector "h2", text: "Which Hackatime project is it?"
    assert_selector ".onboarding-row[data-state=done]", text: "Pixel Pirates"
    find(".hkp__row", text: Hackatime.stubbed_projects["1002"].first.name).click

    assert_selector "h2", text: "Pick your prize.", wait: 5
    assert_selector ".onboarding-prize", count: Prize::ALL.size
    assert_selector ".onboarding-prize.shop-card--rect > .shop-card__shape use[href='#sp-shop-card-rect']", count: Prize::ALL.size, visible: :all
    assert_selector ".onboarding-prize .shop-card__price .shop-card__pace", count: Prize::ALL.size
    assert_equal Prize::ALL.sort_by(&:hours).map(&:name), all(".onboarding-prize .shop-card__name").map(&:text)
    assert_selector ".onboarding-prize[data-picked]", text: Prize::DEFAULT_GOAL.name, count: 1
    find(".onboarding-prize", text: "Keychron K2").click
    assert_selector ".onboarding-prize[data-picked]", text: "Keychron K2", count: 1
    click_on "Next"

    assert_selector "h2", text: "When will you build?"
    assert_selector ".onboarding-row[data-state=done]", text: "Keychron K2"
    assert_equal %w[after\ school evening late\ night weekends], all(".onboarding-time__name").map(&:text)
    assert_button "Start building", disabled: true
    find(".onboarding-time", text: "late night").click
    assert_selector ".onboarding-time:has(:checked)", text: "late night", count: 1
    click_on "Start building"

    assert_current_path project_path, wait: 5
    project = User.find_by!(hca_id: "ident!heidi").project
    assert_equal [ "Pixel Pirates", "https://github.com/heidi/pirates", true, "k2", "late night" ],
                 [ project.title, project.repo_url, project.jame_gam, project.prize_key, project.build_time ]
    assert_equal [ Hackatime.stubbed_projects["1002"].first.name ], project.hackatime_projects
    assert_selector "h1", text: "Pixel Pirates"
    assert_selector ".project__schedule" # D-120: with a repo and a Hackatime project the full page opens at once
    assert_selector ".project__buddy-ask", text: "Bring a buddy"
    assert_text "Keychron K2"
  end

  test "the prize you claimed on the landing page starts picked, unless you've picked another" do
    visit onboarding_path
    execute_script(%(localStorage.setItem("sp-claim", "k2"); localStorage.setItem("sp-goal", "g203")))
    visit onboarding_path
    assert_selector ".onboarding-prize[data-picked]", text: "Keychron K2", count: 1, visible: :all

    execute_script(%(localStorage.removeItem("sp-claim")))
    visit onboarding_path
    assert_selector ".onboarding-prize[data-picked]", text: "Logitech G203", count: 1, visible: :all
  end

  test "signed out, the Hackatime step asks you to sign in with Hack Club, and your answers wait for you" do
    mock_hack_club_auth
    visit onboarding_path
    fill_in "Game name", with: "Pong"
    click_on "Next"

    assert_selector "h2", text: "Which Hackatime project is it?"
    assert_button "Start building", disabled: true, visible: :all
    click_on "Sign in with Hack Club"

    assert_current_path onboarding_path
    assert_selector "h2", text: "Which Hackatime project is it?"
    assert_selector ".onboarding-row[data-state=done]", text: "Pong"
    assert_button "Link Hackatime"
    click_on "Skip for now"

    assert_selector "h2", text: "Pick your prize."
    click_on "Next"
    assert_selector "h2", text: "When will you build?"
    find(".onboarding-time", text: "weekends").click
    click_on "Start building"
    assert_current_path project_path, wait: 5
    assert_equal [ "Pong", [], "weekends" ],
                 User.find_by!(hca_id: "ident!heidi").project.then { |project| [ project.title, project.hackatime_projects, project.build_time ] }
  end

  test "the build time tiles are radios you can pick with the keyboard" do
    sign_in_to_hack_club
    link_hackatime(User.find_by!(hca_id: "ident!heidi"))
    visit onboarding_path
    fill_in "Game name", with: "Pixel Pirates"
    click_on "Next"
    click_on "Skip for now"
    click_on "Next"

    assert_selector "[role=radiogroup][aria-labelledby=onboarding-question-4] input[type=radio]", count: 4, visible: :all
    assert_no_selector ".onboarding-time:has(:checked)"
    find(".onboarding-time__input[value=evening]", visible: :all).send_keys(:space)
    assert_selector ".onboarding-time:has(:checked)", text: "evening", count: 1
    assert_button "Start building", disabled: false
  end

  test "the row after the open step goes on like Next, and only that row" do
    sign_in_to_hack_club
    link_hackatime(User.find_by!(hca_id: "ident!heidi"))
    visit onboarding_path

    assert_selector ".onboarding-row__summary[aria-label='Continue to Hackatime']:not(:disabled)"
    assert_no_selector ".onboarding-row__summary[aria-label='Continue to Prize']"
    find(".onboarding-row__summary[aria-label='Continue to Hackatime']").click
    assert_selector "h2", text: "Which game are you building?" # not ready: Next is disabled, so nothing moved
    assert_selector ".onboarding-row[data-state=active] h2"
    assert_equal "name", evaluate_script("document.activeElement.dataset.onboardingTarget")

    fill_in "Game name", with: "Pixel Pirates"
    find(".onboarding-row__summary[aria-label='Continue to Hackatime']").click
    assert_selector "h2", text: "Which Hackatime project is it?"
    assert_selector ".onboarding-row[data-state=done]", text: "Pixel Pirates"
    assert_no_selector ".onboarding-row__summary[aria-label^='Continue to']"
  end

  test "the picker warns about a project Hackatime links to a different repo than the one you typed, and you can still pick it" do
    before = Hackatime.stubbed_repo_urls
    Hackatime.stubbed_repo_urls = { "1002" => { "heidis-game" => "https://github.com/heidi/other-game" } }
    sign_in_to_hack_club
    link_hackatime(User.find_by!(hca_id: "ident!heidi"))
    visit onboarding_path

    fill_in "Game name", with: "Pixel Pirates"
    fill_in "Code link", with: "github.com/heidi/pirates"
    click_on "Next"

    assert_selector "h2", text: "Which Hackatime project is it?"
    assert_selector ".hkp__row", text: "heidis-game"
    assert_selector ".hkp__warning", text: "Hackatime links this to a different repo", count: 1
    find(".hkp__row", text: "heidis-game").click
    assert_selector "h2", text: "Pick your prize.", wait: 5
  ensure
    Hackatime.stubbed_repo_urls = before
  end

  private
    def sign_in_to_hack_club
      mock_hack_club_auth
      mock_hackatime
      visit onboarding_path
      execute_script(<<~JS)
        const form = document.createElement("form")
        form.method = "post"
        form.action = "/auth/hackclub"
        document.body.append(form)
        form.submit()
      JS
      assert_current_path onboarding_path
    end
end
