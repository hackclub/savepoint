require "test_helper"

# An admin corrects a ship from its page (Ship::Snapshot, Admin::ShipsController#snapshot, Admin::ShipScreenshotsController)
# and reads the repository's README beside it. Only the ship changes. Each edit records who and when, and sends the ship
# to Airtable again.
class Admin::ShipSnapshotsTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                                         changes_made: "Added a second ball.", repo_url: "https://github.com/ana/pong",
                                         demo_url: "https://example.com/pong", screenshot: upload, screenshot_shows_game: true)
    @ship.update_column(:synced_at, 1.minute.ago)
    Web.adapter = ->(*) { Web::Response.new(status: 200, headers: {}, body: "<h1>Pong</h1><p>Two paddles.</p>") }
    sign_in_as(users(:orpheus))
  end

  teardown do
    Rails.configuration.x.admin_slack_ids = @admins
    Web.adapter = nil
  end

  def edit(fields) = patch(snapshot_admin_ship_path(@ship), params: { snapshot: fields })

  test "the fields save to the ship, and the page says who edited it and when" do
    @project = projects(:ana).attributes
    edit(title: "Pong 2", demo_url: "example.com/pong2")
    assert_redirected_to admin_ship_path(@ship)
    @ship.reload
    assert_equal [ "Pong 2", "https://example.com/pong2" ], [ @ship.title, @ship.demo_url ]
    assert_equal [ users(:orpheus), "edit_ship" ], [ @ship.snapshot_edited_by, AdminAuditEvent.last.tool ]
    assert_nil @ship.synced_at, "the next sync sends it again"
    assert_equal @project, projects(:ana).reload.attributes, "the project is its own"

    follow_redirect!
    assert_select "h1", "Pong 2"
    assert_select ".ash__saved", "Snapshot saved."
    assert_select "#snapshot-edited", /Edited by Orpheus the Dino, less than a minute ago/
  end

  test "nothing changed says so" do
    edit(title: "Pong")
    assert_redirected_to admin_ship_path(@ship)
    assert_equal "Nothing changed.", flash[:notice]
    assert_nil @ship.reload.snapshot_edited_at
  end

  test "a field that fails its check comes back with what was typed" do
    edit(title: "", repo_url: "javascript:alert(1)", demo_url: "https://example.com/new")
    assert_response :unprocessable_entity
    assert_select "details#snapshot-edit[open]"
    assert_select "#snapshot-title-error", "Set the title"
    assert_select "#snapshot-repo_url-error", "Add a repository link"
    assert_select "input[name='snapshot[repo_url]'][value=?]", "javascript:alert(1)"
    assert_select "input[name='snapshot[demo_url]'][value=?]", "https://example.com/new"
    assert_select "h1", "Pong", "the page still shows the ship as it is"
    assert_equal "Pong", @ship.reload.title
  end

  test "an admin can't edit their own ship" do
    own = projects(:orpheus).ships.create!(title: "Mine", description: "A game that is mine, with a long enough description.",
                                           repo_url: "https://github.com/o/mine", demo_url: "https://example.com/mine",
                                           screenshot: upload, screenshot_shows_game: true)
    patch snapshot_admin_ship_path(own), params: { snapshot: { title: "Better" } }
    assert_redirected_to admin_ship_path(own)
    assert_equal "Mine", own.reload.title

    post admin_ship_screenshots_path(own), params: { screenshot: upload }, headers: JSON_HEADERS
    assert_response :forbidden
    assert_equal 1, Ship::Snapshot.new(own).screenshots.size

    get admin_ship_path(own)
    assert_select "#snapshot-form", 0
    assert_select ".ash__snapshot", /Someone else edits your own ship/
  end

  test "a participant can't reach the edits" do
    sign_in_as(users(:ana))
    patch snapshot_admin_ship_path(@ship), params: { snapshot: { title: "Mine now" } }
    assert_response :not_found
    post admin_ship_screenshots_path(@ship), params: { screenshot: upload }, headers: JSON_HEADERS
    assert_response :not_found
    assert_equal "Pong", @ship.reload.title
  end

  test "screenshots upload, replace, reorder and remove, each saved at once to the ship" do
    cover_id = Ship::Snapshot.new(@ship).screenshots.first.id

    post admin_ship_screenshots_path(@ship), params: { screenshot: upload }, headers: JSON_HEADERS
    assert_response :created
    added = response.parsed_body["id"].to_i
    assert_match %r{/rails/active_storage/}, response.parsed_body["url"]
    assert_equal [ cover_id, added ], Ship::Snapshot.new(@ship).screenshots.map(&:id)
    assert_nil @ship.reload.synced_at
    assert_equal users(:orpheus), @ship.snapshot_edited_by

    patch order_admin_ship_screenshots_path(@ship), params: { ids: [ added, cover_id ] }, as: :json
    assert_response :no_content
    assert_equal added, @ship.reload.screenshot_attachment.id, "the first is the cover"

    patch order_admin_ship_screenshots_path(@ship), params: { ids: [ added ] }, as: :json
    assert_response :unprocessable_entity
    assert_match(/Reload/, response.parsed_body["error"])

    post admin_ship_screenshots_path(@ship), params: { screenshot: upload, replace: cover_id }, headers: JSON_HEADERS
    assert_response :created
    assert_equal [ added, cover_id ], Ship::Snapshot.new(@ship).screenshots.map(&:id)

    delete admin_ship_screenshot_path(@ship, added), headers: JSON_HEADERS
    assert_response :no_content
    assert_equal [ cover_id ], Ship::Snapshot.new(@ship).screenshots.map(&:id)
    assert @ship.reload.screenshot.attached?, "the last one promoted to the cover"

    delete admin_ship_screenshot_path(@ship, cover_id), headers: JSON_HEADERS
    assert_response :unprocessable_entity
    assert_match(/at least one/, response.parsed_body["error"])
    assert_equal %w[order_ship_screenshots replace_ship_screenshot add_ship_screenshot remove_ship_screenshot].sort,
                 AdminAuditEvent.pluck(:tool).uniq.sort
  end

  test "a GIF is refused" do
    post admin_ship_screenshots_path(@ship), params: { screenshot: Rack::Test::UploadedFile.new(file_fixture("animated.gif"), "image/gif") }, headers: JSON_HEADERS
    assert_response :unprocessable_entity
    assert_match(/not a GIF/, response.parsed_body["error"])
    assert_equal 1, Ship::Snapshot.new(@ship).screenshots.size
  end

  test "the editor lists the screenshots, cover first, and the cover still feeds the page's After" do
    post admin_ship_screenshots_path(@ship), params: { screenshot: upload }, headers: JSON_HEADERS
    get admin_ship_path(@ship)
    ids = Ship::Snapshot.new(@ship).screenshots.map(&:id)
    assert_select "#snapshot-edit .ash__shot-list > li.ash__thumb", 2
    assert_select "#snapshot-edit .ash__shot-list > li.ash__thumb--cover[data-id=?]", ids.first.to_s
    assert_select ".ash__shot-list > li.ash__thumb[data-id=?][aria-label=?]", ids.last.to_s, "Screenshot 2 of 2"
    assert_select ".ash__after img[alt='Screenshot of Pong']"
  end

  test "the README shows open, cleaned, with its images and links in the repository" do
    Web.adapter = lambda do |_method, url, _headers|
      next Web::Response.new(status: 200, headers: {}, body: "[]") unless url.end_with?("/repos/ana/pong/readme")

      Web::Response.new(status: 200, headers: {}, body: %(<h1>Pong</h1><script>alert(1)</script><img src="shot.png"><a href="docs/play.md">play</a><p onclick="x()">Two paddles.</p>))
    end
    get admin_ship_path(@ship)
    assert_select "details.ash__fold[open] #admin-ship-readme-body" do
      assert_select "h1", "Pong"
      assert_select "script", 0
      assert_select "img[src=?]", "https://raw.githubusercontent.com/ana/pong/HEAD/shot.png"
      assert_select "a[href=?]", "https://github.com/ana/pong/blob/HEAD/docs/play.md"
      assert_select "p[onclick]", 0
    end
    assert_select "[data-readme]", 0
  end

  test "a README that can't be shown says why" do
    Web.adapter = ->(*) { Web::Response.new(status: 404, headers: {}, body: "") }
    get admin_ship_path(@ship)
    assert_select "#admin-ship-readme-body", 0
    assert_select ".ash__problem[data-readme=missing]", /ana\/pong has no README/

    Web.adapter = ->(*) { raise Web::Error, "boom" }
    get admin_ship_path(@ship)
    assert_select ".ash__problem[data-readme=error]", /couldn't be reached/
  end

  private
    def upload = Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")

    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
