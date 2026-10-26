require "application_system_test_case"

# The free stickers' card on the project page (D-051), in a real browser: the countdown ticks and the card leads the page.
class StickerPromiseTest < ApplicationSystemTestCase
  setup do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    mock_hackatime
    # The base class freezes the server's clock on 2026-10-24; the sticker window needs an account made after STICKERS_SINCE
    # and the hour not over yet, so the account is made 20 minutes before that clock, and STICKERS_SINCE is moved to suit.
    @since_before = Reward::STICKERS_SINCE
    silence_warnings { Reward.const_set(:STICKERS_SINCE, Time.utc(2026, 10, 1)) }
    users(:orpheus).update_column(:created_at, Time.current - 20.minutes)
    visit onboarding_path
  end

  teardown { silence_warnings { Reward.const_set(:STICKERS_SINCE, @since_before) } }

  test "the card counts the first hour down at the top of the page, before setup" do
    sign_in_and_open_project

    assert_selector ".project__side > .sticker-promise:first-child .sticker-promise__title", text: "Free stickers"
    assert_selector ".sticker-promise__clock b[data-part=m]", text: /\A\d\d\z/
    assert_selector ".sticker-promise__about b[data-controller=local-time]", text: /\d:\d\d [ap]m/
    assert_selector ".sticker-promise__count a", text: "Link your Hackatime project"
    assert_selector ".project__locked", text: "Streaks and the leaderboard open once you're set up."
  end

  test "on a phone the card comes first on the page, above the main column" do
    page.driver.browser.manage.window.resize_to(390, 900)
    sign_in_and_open_project

    card_top = evaluate_script("document.querySelector('.sticker-promise').getBoundingClientRect().top + scrollY")
    main_top = evaluate_script("document.querySelector('.project__main').getBoundingClientRect().top + scrollY")
    assert_operator card_top, :<, main_top
  end

  test "the pomodoro shows the stickers strip with the countdown and progress, and the earned look once the poll says so" do
    start_counting_pomodoro(minutes_logged: 2)

    assert_selector ".focus .focus-stickers[data-kind=counting]", text: /Free stickers: 5 minutes before/
    assert_selector ".focus-stickers__clock b[data-part=m]", text: /\A\d\d\z/
    assert_selector ".focus-stickers__count", text: "2 of 5 minutes"
    assert_selector ".focus-stickers .focus-stickers__progress[aria-valuenow='2']"
    assert_selector ".focus__clock"
    assert_selector ".focus .focus__primary", text: "Pause"

    Hackatime.stubbed_spans = Hackatime.stubbed_spans.merge(users(:orpheus).hackatime_uid => [ hackatime_span(Time.current - 15.minutes, 6) ])
    find(".focus__sync").click
    assert_selector ".focus-stickers[data-kind=earned] .focus-stickers__title", text: "Stickers are yours!"
    assert_selector ".focus-stickers a", text: "Open the shop"
    assert_no_selector ".focus-stickers__clock"
    assert_selector ".focus__clock" # still in the pomodoro, not sent to the shop
  end

  private
    # The overlay open on a counting account that has logged some minutes on its linked game since signing up.
    def start_counting_pomodoro(minutes_logged:)
      link_hackatime(users(:orpheus))
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      Hackatime.stubbed_spans = Hackatime.stubbed_spans.merge(users(:orpheus).hackatime_uid => [ hackatime_span(Time.current - 15.minutes, minutes_logged) ])
      sign_in_and_open_project
      # The server's clock is frozen in the past (the base class), the browser's is not: line them up, or the countdown has run out.
      execute_script("const real = Date.now.bind(Date); const off = arguments[0] - real(); Date.now = () => real() + off", (Time.current.to_f * 1000).to_i)
      click_on "Start pomodoro"
      assert_selector ".focus__label", text: "LOCKED IN · ROUND 1"
    end

    def sign_in_and_open_project
      execute_script(<<~JS)
        const form = document.createElement("form")
        form.method = "post"
        form.action = "/auth/hackclub"
        document.body.append(form)
        form.submit()
      JS
      assert_current_path onboarding_path
      visit project_path
      assert_selector "h1", text: "a rhythm game"
    end
end
