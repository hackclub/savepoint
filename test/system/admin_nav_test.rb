require "application_system_test_case"
require_relative "../support/admin_mcp_helpers"

# The admin bar is in one place on every admin page (layouts/save_point renders it, above the page), so it doesn't
# jump about as you go from page to page. It's measured on each, wide and on a phone.
class AdminNavTest < ApplicationSystemTestCase
  include AdminMcpHelpers

  setup do
    create_insights_views
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "the bar has the same place and size on every admin page, wide and narrow" do
    sign_in
    pages = [ admin_root_path, admin_orders_path, admin_ships_path, admin_extensions_path, admin_projects_path,
              admin_users_path, admin_user_path(users(:ana)), admin_metrics_path, admin_stats_path, admin_nudges_path,
              admin_tokens_path ]

    [ [ 1440, 1000 ], [ 400, 900 ] ].each do |width, height|
      page.current_window.resize_to(width, height)
      rects = pages.to_h do |path|
        visit path
        assert_selector ".admin-bar"
        [ path, measure_bar ]
      end
      rects.each { |path, rect| assert_equal rects.values.first, rect, "#{path} has the bar somewhere else at #{width}px" }
    end
  end

  test "the bar keeps its place when one page turns into another" do
    sign_in
    visit admin_root_path
    before = measure_bar
    within(".admin__nav") { click_on "Stats" }
    assert_selector "h1", text: "Save Point in numbers"
    assert_equal before, measure_bar
    assert_selector ".admin__nav a[aria-current=page]", text: "Stats"
    assert_equal "admin-bar", evaluate_script("getComputedStyle(document.querySelector('.admin-bar')).viewTransitionName")
  end

  test "screenshots of a few admin pages, when ADMIN_NAV_SHOTS names a folder" do
    dir = ENV["ADMIN_NAV_SHOTS"]
    skip "set ADMIN_NAV_SHOTS to a folder to take screenshots" unless dir
    sign_in
    page.current_window.resize_to(1440, 1000)
    FileUtils.mkdir_p(dir)
    { "home" => admin_root_path, "ships" => admin_ships_path, "metrics" => admin_metrics_path, "stats" => admin_stats_path,
      "users" => admin_users_path, "orders" => admin_orders_path }.each do |name, path|
      visit path
      assert_selector ".admin-bar"
      page.save_screenshot(File.join(dir, "#{name}.png"))
    end
  end

  private
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

    def measure_bar
      evaluate_script(<<~JS)
        (() => { const r = document.querySelector(".admin-bar").getBoundingClientRect(); return [ r.left, r.top, r.width, r.height ].map((n) => Math.round(n * 100) / 100) })()
      JS
    end
end
