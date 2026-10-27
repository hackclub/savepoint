require "application_system_test_case"

# D-099 and D-100: shipping again needs a new hour, and the later form lists the commits since the last ship.
# Set SHIP_SHOTS=/some/dir to keep a screenshot of each state.
class ShipAgainTest < ApplicationSystemTestCase
  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @project = @user.project
    @project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true, repo_url: "https://github.com/orpheus/beat-sheet")
    mock_hack_club_auth(uid: @user.hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    visit onboarding_path
    execute_script(<<~JS)
      const form = document.createElement("form")
      form.method = "post"
      form.action = "/auth/hackclub"
      document.body.append(form)
      form.submit()
    JS
    assert_current_path onboarding_path
    page.driver.browser.manage.window.resize_to(1400, 1500)
  end

  teardown { Web.adapter = nil }

  test "under an hour of new time, the ship page says how many hours are left" do
    log_hours(@user, 2.6)
    approved_ship(2.0)
    visit project_path
    assert_no_selector ".project__ship"
    visit project_ship_path

    assert_text "Build a little more first."
    assert_text "Log 0.4 more hrs on"
    assert_no_selector "form.ship__form"
    shot("wait")
  end

  test "an hour of new time opens a form that asks what changed and lists the commits since the last ship" do
    log_hours(@user, 4.0)
    approved_ship(2.0)
    commits = [ [ "Add a combo meter", 1.day.ago ], [ "Fix the late-hit window so it feels fair", 2.days.ago ], [ "New menu art", 3.days.ago ] ].map do |message, date|
      { "sha" => SecureRandom.hex(4), "html_url" => "https://github.com/orpheus/beat-sheet/commit/x",
        "commit" => { "message" => "#{message}\n\nmore", "author" => { "name" => "Orpheus", "date" => date.iso8601 } } }
    end
    Web.adapter = lambda do |_method, url, _headers|
      url.include?("/commits") ? Web::Response.new(status: 200, headers: {}, body: commits.to_json) : Web::Response.new(status: 404, headers: {}, body: "{}")
    end
    visit project_ship_path

    assert_text(/what changed since your last ship\?/i)
    assert_selector ".ship__commit", count: 3
    assert_equal "", find("#ship_changes_made").value
    shot("later-form")
  end

  private
    def approved_ship(hours)
      @project.ships.new(title: "v1", description: "x" * 50, repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://a.itch.io/b",
                         hours:, status: "approved", approved_hours: hours, created_at: 4.days.ago).save!(validate: false)
    end

    def shot(name)
      save_screenshot(File.join(ENV["SHIP_SHOTS"], "#{name}.png")) if ENV["SHIP_SHOTS"]
    end
end
