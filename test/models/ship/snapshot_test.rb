require "test_helper"

class Ship::SnapshotTest < ActiveSupport::TestCase
  setup do
    @admin = users(:orpheus)
    @ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                                         changes_made: "Added a second ball.", repo_url: "https://github.com/ana/pong",
                                         demo_url: "https://example.com/pong", screenshot: upload, screenshot_shows_game: true)
    @ship.update_column(:synced_at, 1.minute.ago)
    @snapshot = Ship::Snapshot.new(@ship)
  end

  test "a changed field saves to the ship, and records who, when, the audit and a resync" do
    project = projects(:ana).attributes
    freeze_time do
      assert_equal true, @snapshot.update({ title: "Pong 2", description: "Two paddles, two balls, and every frame is a sprite.", repo_url: "github.com/ana/pong2" }, by: @admin)
      @ship.reload
      assert_equal [ "Pong 2", "https://github.com/ana/pong2" ], [ @ship.title, @ship.repo_url ]
      assert_equal [ @admin, Time.current ], [ @ship.snapshot_edited_by, @ship.snapshot_edited_at ]
      assert_nil @ship.synced_at
      event = AdminAuditEvent.last
      assert_equal [ @admin, "edit_ship", { "ship_id" => @ship.id } ], [ event.user, event.tool, event.ids ]
    end
    assert_equal project, projects(:ana).reload.attributes, "only the ship changes"
  end

  test "what they changed alone still resyncs, though it is not an Airtable column" do
    assert_equal true, @snapshot.update({ changes_made: "Added two balls." }, by: @admin)
    assert_equal "Added two balls.", @ship.reload.changes_made
    assert_nil @ship.synced_at
  end

  test "nothing changed writes nothing" do
    assert_nil @snapshot.update({ title: " Pong ", description: @ship.description }, by: @admin)
    assert_nil @ship.reload.snapshot_edited_at
    assert @ship.synced_at
    assert_equal 0, AdminAuditEvent.count
  end

  test "an invalid field comes back with what was typed, and the ship stays as it was" do
    assert_equal false, @snapshot.update({ title: "", repo_url: "javascript:alert(1)" }, by: @admin)
    assert_equal "Set the title", @snapshot.errors.messages_for(:title).first
    assert_equal "Add a repository link", @snapshot.errors.messages_for(:repo_url).first
    assert_equal "javascript:alert(1)", @snapshot.repo_url
    assert_equal [ "Pong", "https://github.com/ana/pong" ], [ @ship.reload.title, @ship.repo_url ]
    assert_nil @ship.snapshot_edited_at
  end

  test "a field that was already wrong and isn't touched doesn't block the edit" do
    @ship.update_column(:description, "Too short")
    assert_equal true, Ship::Snapshot.new(@ship.reload).update({ title: "Pong 2" }, by: @admin)
    assert_equal "Pong 2", @ship.reload.title
  end

  test "the admin's own ship is theirs" do
    assert @snapshot.own?(users(:ana))
    assert_not @snapshot.own?(@admin)
  end

  test "the cover is the ship's screenshot, and an added one goes after it" do
    cover = @snapshot.screenshots.first
    added = @snapshot.add_screenshot(upload_file, by: @admin)
    assert_equal [ cover.id, added.id ], @snapshot.screenshots.map(&:id)
    assert_equal cover.blob, @ship.reload.screenshot.blob
    assert_nil @ship.synced_at
    assert_equal "add_ship_screenshot", AdminAuditEvent.last.tool
  end

  test "an order picks a new cover, and a ship's screenshot follows it" do
    cover = @snapshot.screenshots.first
    second = @snapshot.add_screenshot(upload_file, by: @admin)
    third = @snapshot.add_screenshot(upload_file, by: @admin)

    @snapshot.order_screenshots([ third.id, cover.id, second.id ], by: @admin)
    assert_equal [ third.id, cover.id, second.id ], @snapshot.screenshots.map(&:id)
    assert_equal third.blob, @ship.reload.screenshot.blob, "everything that reads ship.screenshot sees the new cover"

    @snapshot.order_screenshots([ second.id, third.id, cover.id ], by: @admin)
    assert_equal [ second.id, third.id, cover.id ], @snapshot.screenshots.map(&:id)
    assert_equal "order_ship_screenshots", AdminAuditEvent.last.tool
  end

  test "an order that isn't the ship's screenshots is refused" do
    cover = @snapshot.screenshots.first
    assert_raises(Ship::Snapshot::Refused) { @snapshot.order_screenshots([ cover.id, cover.id + 999 ], by: @admin) }
    assert_raises(Ship::Snapshot::Refused) { @snapshot.order_screenshots([], by: @admin) }
  end

  test "a replacement takes the place, keeps the order, and lets go of a blob nothing else shows" do
    cover = @snapshot.screenshots.first
    second = @snapshot.add_screenshot(upload_file, by: @admin)
    old = second.blob

    @snapshot.add_screenshot(upload_file, by: @admin, replace: second.id)
    assert_equal [ cover.id, second.id ], @snapshot.screenshots.map(&:id)
    assert_not_equal old, @snapshot.screenshots.last.blob
    assert_equal "replace_ship_screenshot", AdminAuditEvent.last.tool
  end

  test "removing the cover promotes the next one, and the last one can't go" do
    cover = @snapshot.screenshots.first
    second = @snapshot.add_screenshot(upload_file, by: @admin)

    @snapshot.remove_screenshot(cover.id, by: @admin)
    assert_equal [ second.id ], @snapshot.screenshots.map(&:id)
    assert_equal second.blob, @ship.reload.screenshot.blob
    assert_equal "remove_ship_screenshot", AdminAuditEvent.last.tool

    assert_raises(Ship::Snapshot::Refused) { @snapshot.remove_screenshot(second.id, by: @admin) }
    assert_raises(Ship::Snapshot::Refused) { @snapshot.remove_screenshot(second.id + 999, by: @admin) }
  end

  test "the project keeps its screenshot when the ship's goes" do
    projects(:ana).screenshot.attach(@ship.screenshot.blob)
    @snapshot.add_screenshot(upload_file, by: @admin)
    @snapshot.remove_screenshot(@snapshot.screenshots.first.id, by: @admin)
    assert projects(:ana).reload.screenshot.attached?
    assert projects(:ana).screenshot.blob.persisted?
  end

  test "a ship holds six screenshots, still PNG, JPEG or WebP, under 5 MB" do
    5.times { @snapshot.add_screenshot(upload_file, by: @admin) }
    error = assert_raises(Ship::Snapshot::Refused) { @snapshot.add_screenshot(upload_file, by: @admin) }
    assert_match(/up to 6/, error.message)

    @snapshot.remove_screenshot(@snapshot.screenshots.last.id, by: @admin)
    gif = Rack::Test::UploadedFile.new(file_fixture("animated.gif"), "image/gif")
    assert_match(/not a GIF/, assert_raises(Ship::Snapshot::Refused) { @snapshot.add_screenshot(uploaded(gif), by: @admin) }.message)
    assert_match(/Choose an image/, assert_raises(Ship::Snapshot::Refused) { @snapshot.add_screenshot(nil, by: @admin) }.message)
    assert_equal 5, @snapshot.screenshots.size
  end

  private
    def upload = Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")

    # What a controller hands over: an ActionDispatch upload.
    def upload_file = uploaded(upload)

    def uploaded(file)
      ActionDispatch::Http::UploadedFile.new(tempfile: file.tempfile, filename: file.original_filename, type: file.content_type)
    end
end
