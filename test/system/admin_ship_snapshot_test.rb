require "application_system_test_case"

# The admin ship page's screenshot editor, in a real browser: a file chosen lands on the end, the arrow keys move one,
# and its x removes one. Each saves at once to the ship. The README is open beside it.
class AdminShipSnapshotSystemTest < ApplicationSystemTestCase
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                                         repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong",
                                         screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                                         screenshot_shows_game: true)
    Web.adapter = lambda do |_method, url, _headers|
      body = url.end_with?("/readme") ? "<h1>Pong</h1><p>Two paddles.</p>" : "[]"
      Web::Response.new(status: 200, headers: {}, body:)
    end
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
    # The upload sends the page's CSRF token, which only renders with this on (after signing in, which posts without one).
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
    Rails.configuration.x.admin_slack_ids = @admins
    Web.adapter = nil
  end

  test "an upload, a move and a removal each save to the ship, and the README is open" do
    visit admin_ship_path(@ship)
    assert_selector "#admin-ship-readme-body h1", text: "Pong"

    find("#snapshot-edit summary").click
    cover = Ship::Snapshot.new(@ship).screenshots.first
    find("#snapshot-edit input[type=file]", visible: :all).set(file_fixture("screenshot.png").to_s)
    assert_selector "#snapshot-shot-status", text: "Uploaded."
    added = Ship::Snapshot.new(@ship).screenshots.last
    assert_not_equal cover.id, added.id

    find(".ash__thumb[data-id='#{added.id}']").send_keys(:left)
    assert_selector "#snapshot-shot-status", text: "Moved to 1 of 2."
    assert_selector ".ash__thumb--cover[data-id='#{added.id}']"
    wait_for { @ship.reload.screenshot_attachment.id == added.id }
    assert_equal [ added.id, cover.id ], Ship::Snapshot.new(@ship).screenshots.map(&:id)

    find(".ash__thumb[data-id='#{cover.id}'] .ash__thumb-remove").click
    assert_selector "#snapshot-shot-status", text: "Removed."
    assert_equal [ added.id ], Ship::Snapshot.new(@ship).screenshots.map(&:id)

    visit admin_ship_path(@ship)
    assert_selector "#snapshot-edited", text: /Edited by .+ ago/
  end

  private
    def wait_for(seconds = 3)
      deadline = Time.current + seconds
      sleep 0.05 until yield || Time.current > deadline
    end
end
