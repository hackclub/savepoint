require "application_system_test_case"
require_relative "../support/admin_mcp_helpers"

# D-114: the admin projects list fits its panel at every width, with long emails, ideas and Hackatime lists wrapping instead of
# scrolling sideways, and its headings sort it. Measured in a real browser. Set D114_SHOTS to a folder to take screenshots.
class AdminProjectsTest < ApplicationSystemTestCase
  include AdminMcpHelpers

  LONG_HACKATIME = [ "excuse-me,-pardon-me", "Excuse Me, Pardon Me", "a-very-long-hackatime-project-name-that-goes-on", "second-prototype-of-the-game",
                     "sound-effects-and-music-experiments", "dotfiles" ].freeze

  setup do
    @admins = Rails.configuration.x.admin_slack_ids # first: the teardown runs even when a line below raises
    create_insights_views
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    seed_projects
    sign_in
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Rails.configuration.x.admin_slack_ids = @admins
  end

  test "the table fits its panel and the page at every width, with long cells wrapping" do
    [ 1024, 1280, 1440, 390 ].each do |width|
      resize(width, 1000)
      visit admin_projects_path(sort: "hours", dir: "desc")
      assert_selector "tbody tr", minimum: 8
      sizes = measure
      puts "width #{width}: panel #{sizes['panelScroll']}/#{sizes['panelClient']}, page #{sizes['pageScroll']}/#{sizes['pageClient']}, table #{sizes['table']}"
      assert_operator sizes["panelScroll"], :<=, sizes["panelClient"], "the panel scrolls sideways at #{width}px"
      assert_operator sizes["pageScroll"], :<=, sizes["pageClient"], "the page scrolls sideways at #{width}px"
      assert_selector "thead a[data-sort=hours]", visible: true
      assert_operator sizes["table"], :<=, sizes["panelClient"], "the table is wider than its panel at #{width}px"
    end
  end

  test "a heading sorts the list, a second click reverses it, and the search is kept" do
    resize(1280, 1000)
    visit admin_projects_path(q: "hackclub.com")
    click_on "Hours"
    assert_selector "th[aria-sort=descending]", text: /hours/i
    top = first_row_hours
    click_on "Hours"
    assert_selector "th[aria-sort=ascending]", text: /hours/i
    assert_operator first_row_hours, :<=, top
    assert_equal "hackclub.com", find("input[name=q]").value
    assert_current_path(/q=hackclub.com/, url: true)
  end

  test "screenshots, when D114_SHOTS names a folder" do
    dir = ENV["D114_SHOTS"]
    skip "set D114_SHOTS to a folder to take screenshots" unless dir
    FileUtils.mkdir_p(dir)
    { 1280 => "list-1280-hours", 1440 => "list-1440-hours", 390 => "list-390" }.each do |width, name|
      resize(width, 1100)
      visit admin_projects_path(sort: "hours", dir: "desc")
      assert_selector "tbody tr", minimum: 8
      page.save_screenshot(File.join(dir, "#{name}.png"))
    end
    resize(1280, 1100)
    visit admin_projects_path(sort: "hours", dir: "desc")
    heading = find("th[aria-sort]")
    heading.native.save_screenshot(File.join(dir, "header-hours-arrow.png"))
    puts "heading #{evaluate_script('(() => { const r = document.querySelector("th[aria-sort]").getBoundingClientRect(); return [r.width, r.height] })()')}"
  end

  private
    # Eight long ones, then one of each state whose cell won't wrap: a ship in review, a ship sent back, a buddy with a long title,
    # and Hackatime linked with no project.
    def seed_projects
      8.times do |index|
        handle = "long#{index}"
        user = User.create!(hca_id: "ident!#{handle}", name: "Participant Number #{index}", first_name: "P#{index}",
                            email: "a.very.long.email.address.for.testing.#{handle}@subdomain.example-school-district.org",
                            slack_display_name: "a-long-slack-display-name-#{index}", hackatime_uid: (4000 + index).to_s,
                            hackatime_access_token: "token-#{handle}", current_streak: index)
        prize = Prize::ALL[index * 2 % Prize::ALL.size].key
        Project.create!(user:, idea: "A long idea about #{index} games, with a great many words in it, so that it must wrap onto several lines of the table",
                        prize_key: prize, pace_minutes: 45, build_time: "late night", signed_on: "2026-09-30",
                        hackatime_projects: index.even? ? LONG_HACKATIME : [ "short" ])
        user.streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: (index + 1) * 3000)
      end
      seed_states
    end

    def seed_states
      mine = Project.where("idea LIKE 'A long idea about %'").order(:id).to_a
      ship = ->(project, status) {
        project.ships.create!(title: "Ship", description: "Two paddles, one ball, and every frame is a sprite.", repo_url: "https://github.com/x/y",
                              demo_url: "https://example.com/x", hours: 1, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                              screenshot_shows_game: true).tap { it.update_columns(status:) }
      }
      ship.(mine[0], "in_review")
      ship.(mine[1], "changes_needed")
      mine[2].update_columns(buddy_invited: true)
      mine[3].update_columns(hackatime_projects: [])
      mine[4].update_columns(name: "A buddy game with a very long title that goes on and on")
      mine[5].update_columns(name: "Another long-titled buddy game for the pairing")
      Pair.create!(first_project: mine[4], second_project: mine[5], started_on: Date.current)
    end

    def sign_in
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
      visit root_path
      execute_script(<<~JS)
        const form = document.createElement("form")
        form.method = "post"
        form.action = "/auth/hackclub"
        document.body.append(form)
        form.submit()
      JS
      assert_selector ".top-bar"
    end

    def measure
      evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector(".pg-admin-projects__panel")
          const doc = document.documentElement
          return { panelScroll: panel.scrollWidth, panelClient: panel.clientWidth, pageScroll: doc.scrollWidth, pageClient: doc.clientWidth,
                   table: Math.round(document.querySelector(".pg-admin-projects__table").getBoundingClientRect().width) }
        })()
      JS
    end

    # The window can't go below about 500px wide, so a phone is the page's own viewport at that size.
    def resize(width, height)
      page.current_window.resize_to(1400, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: false)
    end

    def first_row_hours = find("tbody tr:first-child td[data-label=Hours]").text.to_f
end
