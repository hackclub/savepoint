require "test_helper"

# Chrome sometimes answers "Node with given id does not belong to the document" (an UnknownError) when Capybara asks
# whether an element is visible just as Turbo swaps the page. It's the same race as a stale element, so Capybara
# retries it like one until the wait runs out, and a real failure still raises then.
module RetryNodeGone
  def invalid_element_errors = super + [ Selenium::WebDriver::Error::UnknownError ]
end
Capybara::Selenium::Driver.prepend(RetryNodeGone)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Muted: the pomodoro plays lofi and the bot cheers, out loud on whoever's running the tests.
  SCREEN_SIZE = [ 1400, 1400 ].freeze

  driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE do |options|
    options.add_argument("--mute-audio")
  end

  setup do
    # A fixed clock on day 2 of the program, so nothing depends on the real one. The app server runs in this process,
    # so it sees it too. Program::DATES begins on the launch day, and every sign-in or page view syncs the days from
    # then to today from Hackatime's spans (StreakActivity.sync_for_user!), which would overwrite hours seeded as rows.
    travel_to Time.utc(2026, 10, 24, 12)
    @spans_before = Hackatime.stubbed_spans
    # Chrome, the server and a page's fetches run on one machine, which can be busy: 2 s is short for them.
    @max_wait_before = Capybara.default_max_wait_time
    Capybara.default_max_wait_time = 5
    # These tests sign in with the stubbed Hack Club Auth and link Hackatime on their own pages. A local .env with
    # HACKATIME_CLIENT_ID and HACKATIME_CHAIN=1 would chain sign-in on to Hackatime's OAuth (D-026), so it's off for every system test.
    @hackatime_chain_before = Rails.configuration.x.hackatime_chain
    Rails.configuration.x.hackatime_chain = false
  end

  teardown do
    # One browser serves every test, so a test that shrinks it to a phone would leave the next one, in random order,
    # on the phone layout. Put it back.
    page.current_window.resize_to(*SCREEN_SIZE)
    Rails.configuration.x.hackatime_chain = @hackatime_chain_before
    Hackatime.stubbed_spans = @spans_before
    Capybara.default_max_wait_time = @max_wait_before
  end

  private
    # The sidebar's cards grow and shrink over 230 to 300 ms (side_sections_controller.js), moving whatever is under
    # them. A click while they move can land on a neighbour, so wait until none is animating.
    def wait_for_side_sections
      page.document.synchronize do
        settled = evaluate_script(<<~JS)
          [ ...document.querySelectorAll(".side-section") ].every((card) => card.getAnimations({ subtree: true }).length === 0)
        JS
        raise Capybara::ExpectationNotMet, "the sidebar is still moving" unless settled
      end
    end

    # A prize's sheet pops in over 420 ms, overshooting its size (order-sheet-pop). A click while it moves can miss its
    # button, so wait until that animation has finished.
    def wait_for_sheet(selector)
      page.document.synchronize do
        settled = evaluate_script(<<~JS, selector)
          (() => {
            const card = document.querySelector(arguments[0] + " .order-sheet__card")
            return !!card && !card.getAnimations().some((animation) => animation.animationName === "order-sheet-pop")
          })()
        JS
        raise Capybara::ExpectationNotMet, "#{selector} is still opening" unless settled
      end
    end

    # Hackatime says this user built `hours` on the first program day, and the next sync turns that into the day's hours.
    def log_hours(user, hours)
      span = hackatime_span(Program::STARTS_AT + 3.hours, (hours * 60).ceil)
      Hackatime.stubbed_spans = Hackatime.stubbed_spans.merge(user.hackatime_uid => [ span ])
      user.update_column(:streak_synced_at, nil)
      StreakActivity.sync_for_user!(user.reload)
    end

    # Selenium measures click offsets from the visible part of the (very wide) grid,
    # so dispatch the click at exact coordinates instead.
    def click_cell(column:, row:, type: "click")
      execute_script(<<~JS, column, row, type)
        const grid = document.querySelector(".sheet__cells")
        const { left, top } = grid.getBoundingClientRect()
        grid.dispatchEvent(new MouseEvent(arguments[2], {
          bubbles: true, clientX: left + arguments[0] * 100 + 50, clientY: top + arguments[1] * 30 + 15
        }))
      JS
    end

    def assert_selection(address, formula:)
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: address
      assert_equal formula, find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    end
end
