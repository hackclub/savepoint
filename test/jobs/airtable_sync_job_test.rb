require "test_helper"

# The rolling Postgres to Airtable copy, against a fake Airtable.
class AirtableSyncJobTest < ActiveSupport::TestCase
  SUBMISSIONS = "tblvPYnH7OouAeFkC"

  class FakeAirtable
    attr_reader :upserts
    attr_accessor :existing, :fail_on, :fail_table

    def initialize
      @upserts = []
      @existing = {}
    end

    def upsert(table, rows, merge_on:)
      raise AirtableClient::Error, "Airtable answered 422 INVALID_VALUE_FOR_COLUMN" if table == fail_table || rows.any? { fail_on&.include?(it[merge_on]) }
      @upserts << [ table, rows ]
      rows.to_h { [ it[merge_on], { "id" => "rec#{it[merge_on]}", "fields" => it } ] }
    end

    def find_by(_table, _field, values) = existing.slice(*values)

    def rows(table) = upserts.select { it.first == table }.flat_map(&:last)
  end

  setup do
    @fake = FakeAirtable.new
    fake = @fake
    AirtableClient.define_singleton_method(:new) { |*| fake }
    config = Rails.application.config_for(:airtable).merge(enabled: true)
    @config = config
    Rails.application.define_singleton_method(:config_for) { |name, **| name == :airtable ? config : super(name) }
    @orpheus = projects(:orpheus)
    # The Unified YSWS DB has no earlier record of any game here, unless a test says otherwise.
    Ship::EarlierShip.token = "pat-test"
    Web.adapter = ->(*) { Web::Response.new(status: 200, headers: {}, body: { records: [] }.to_json) }
  end

  teardown do
    Rails.application.singleton_class.remove_method(:config_for)
    AirtableClient.singleton_class.remove_method(:new)
    Web.adapter = nil
    Ship::EarlierShip.token = nil
  end

  def upload = Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")

  def approved_ship(approved_hours: 10)
    @orpheus.user.update!(name: "Orpheus the Dino", first_name: "Orpheus", hackatime_uid: "1001", birthdate: "2010-04-01")
    ship = @orpheus.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                  repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/play",
                                  hackatime_projects: [ "rhythm-game" ], hours: 12.5, screenshot: upload, screenshot_shows_game: true)
    ship.update!(approved_columns(approved_hours))
    ship
  end

  test "copies each table to its own, with the stable id, and marks the rows synced" do
    Airtable::SyncJob.perform_now
    assert_equal %w[Users Projects], @fake.upserts.map(&:first).uniq
    assert_includes @fake.rows("Users").map { it["save_point_id"] }, "user-#{@orpheus.user_id}"
    assert_includes @fake.rows("Projects").map { it["save_point_id"] }, "project-#{@orpheus.id}"
    assert User.where(synced_at: nil).none?
    assert Project.where(synced_at: nil).none?
    assert_equal "recuser-#{@orpheus.user_id}", @orpheus.user.reload.airtable_record_id
  end

  test "copies orders to their own table" do
    approved_ship(approved_hours: 100)
    order = @orpheus.reload.orders.create!(prize_key: @orpheus.prize_key)
    Airtable::SyncJob.perform_now
    row = @fake.rows("Orders").find { it["save_point_id"] == "order-#{order.id}" }
    assert_not row.key?("Email"), "the project id leads to the user"
    assert_equal "waiting", row["Status"]
    assert_not row.key?("Address (Line 1)")
    assert_not row.keys.any? { it.match?(/address|recipient/i) }
  end

  test "copies approved ships to the submission table, but not ones in review" do
    ship = approved_ship
    review = projects(:ana).ships.create!(title: "Pong", description: "Pong, but every paddle is a cat in a very small box.",
                                          repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong",
                                          screenshot: upload, screenshot_shows_game: true)
    Airtable::SyncJob.perform_now
    rows = @fake.rows(SUBMISSIONS)
    assert_equal [ "ship-#{ship.id}" ], rows.map { it["save_point_id"] }
    row = rows.first
    assert_equal "https://github.com/orpheus/beat-sheet", row["Code URL"]
    assert_equal "https://example.com/play", row["Playable URL"]
    assert_equal 10.0, row["Optional - Override Hours Spent"]
    assert_equal "orpheus", row["GitHub Username"]
    assert_equal "the Dino", row["Last Name"], "what is left of the name after the first name"
    assert_equal [ "15 Falls Rd", "Shelburne", "VT", "05482", "US" ],
                 row.values_at("Address (Line 1)", "City", "State / Province", "ZIP / Postal Code", "Country")
    assert_equal "2010-04-01", row["Birthday"]
    assert_equal "1001", row["Justification - Submitter Hackatime ID"]
    assert_match "rhythm-game", row["Justification - Hackatime Project Name(s) + Date Range(s)"]
    assert_nil review.reload.airtable_record_id
    assert_not row.key?("Automation - Submit to Unified YSWS")
    assert_not row.key?("Optional - Override Hours Spent Justification")
  end

  test "a ship waiting for its fraud check does not go to Airtable until it passes (D-063)" do
    ship = approved_ship
    ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", approved_hours: nil, review_hours: 10)
    Airtable::SyncJob.perform_now
    assert_empty @fake.rows(SUBMISSIONS)

    ship.update_columns(status: "approved", fraud_status: "passed", approved_hours: 10)
    ship.project.touch
    Airtable::SyncJob.perform_now
    assert_equal [ "ship-#{ship.id}" ], @fake.rows(SUBMISSIONS).map { it["save_point_id"] }
  end

  test "a ship whose code URL the Unified YSWS DB can't be asked about waits, rather than going without its duplicate justification" do
    ship = approved_ship
    Web.adapter = ->(*) { raise Web::Error, "timeout" }
    Airtable::SyncJob.perform_now
    assert_empty @fake.rows(SUBMISSIONS)
    assert_not_nil ship.reload.airtable_failed_at
    assert_nil ship.synced_at
    Ship::EarlierShip.token = nil
    travel 61.minutes do
      Airtable::SyncJob.perform_now
      assert_empty @fake.rows(SUBMISSIONS), "not configured is not checked either"
    end
    Ship::EarlierShip.token = "pat-test"
    Web.adapter = ->(*) { Web::Response.new(status: 200, headers: {}, body: { records: [] }.to_json) }
    travel 122.minutes do
      Airtable::SyncJob.perform_now
      assert_equal [ "ship-#{ship.id}" ], @fake.rows(SUBMISSIONS).map { it["save_point_id"] }
    end
  end

  test "the submission row carries a screenshot link only when APP_URL is set" do
    ship = approved_ship
    assert_nil AirtableFields.ship(ship)["Screenshot"]
    ENV["APP_URL"] = "https://savepoint.hackclub.com"
    url = AirtableFields.ship(ship)["Screenshot"].first["url"]
    assert url.start_with?("https://savepoint.hackclub.com/rails/active_storage/blobs/redirect/"), url
    signed = url.split("/redirect/").last.split("/").first
    assert_equal ship.screenshot.blob, ActiveStorage::Blob.find_signed!(signed)
    travel 2.hours do
      assert_nil ActiveStorage::Blob.find_signed(signed), "the link expires"
    end
  ensure
    ENV.delete("APP_URL")
  end

  test "a user's phone, token and timezone never go to Airtable" do
    @orpheus.user.update!(phone_number: "+18025550123", hackatime_access_token: "secret-token", timezone: "America/New_York")
    Airtable::SyncJob.perform_now
    sent = @fake.upserts.to_json
    assert_no_match(/\+18025550123|secret-token|New_York/, sent)
  end

  test "every field a row writes exists in the schema" do
    ship = approved_ship(approved_hours: 100)
    order = @orpheus.reload.orders.create!(prize_key: @orpheus.prize_key)
    assert_empty AirtableFields.user(ship.project.user).keys - AirtableSchema.field_names(:users)
    assert_empty AirtableFields.project(@orpheus).keys - AirtableSchema.field_names(:projects)
    assert_empty AirtableFields.order(order).keys - AirtableSchema.field_names(:orders)
    assert_empty AirtableFields.ship(ship).keys - AirtableSchema.field_names(:ships)
  end

  test "never overwrites a ship the Unified YSWS DB has taken" do
    ship = approved_ship
    @fake.existing = { "ship-#{ship.id}" => { "fields" => { "Automation - YSWS Record ID" => "recUNIFIED" } } }
    Airtable::SyncJob.perform_now
    assert_empty @fake.rows(SUBMISSIONS)
    assert ship.reload.in_unified
    @fake.upserts.clear
    Airtable::SyncJob.perform_now
    assert_empty @fake.rows(SUBMISSIONS), "a taken ship is not looked at again"
  end

  test "a ship goes once and is not sent again until it changes, and its screenshot goes only the first time" do
    ENV["APP_URL"] = "https://savepoint.hackclub.com"
    ship = approved_ship
    Airtable::SyncJob.perform_now
    assert @fake.rows(SUBMISSIONS).first["Screenshot"]
    assert_not_nil ship.reload.synced_at
    assert_equal "recship-#{ship.id}", ship.airtable_record_id
    @fake.upserts.clear
    5.times { Airtable::SyncJob.perform_now }
    assert_empty @fake.rows(SUBMISSIONS), "no rotation for ships, so a reviewer's edits stay"
    ship.update!(description: "A rhythm game where every beat is a cell lighting up. Now with a combo meter.")
    Airtable::SyncJob.perform_now
    row = @fake.rows(SUBMISSIONS).first
    assert_match "combo meter", row["Description"]
    assert_not row.key?("Screenshot")
  ensure
    ENV.delete("APP_URL")
  end

  test "a change to the user's name, address or birthday sends their approved ships again" do
    ship = approved_ship
    Airtable::SyncJob.perform_now
    assert_not_nil ship.reload.synced_at
    @orpheus.user.update!(slack_muted_at: Time.current)
    assert_not_nil ship.reload.synced_at
    @orpheus.user.update!(birthdate: "2010-05-01")
    assert_nil ship.reload.synced_at
    Airtable::SyncJob.perform_now
    ship.reload
    assert_not_nil ship.synced_at
    @orpheus.user.update!(address: { "street_address" => "1 New St", "locality" => "Town", "country" => "US" })
    assert_nil ship.reload.synced_at
  end

  test "a second approved ship sends only its new hours" do
    first = approved_ship(approved_hours: 10)
    second = @orpheus.ships.create!(title: "Beat Sheet 2", description: "A rhythm game where every beat is a cell lighting up in time, again.",
                                    repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/play",
                                    hours: 15, screenshot: upload, screenshot_shows_game: true)
    second.update!(approved_columns(15))
    third = @orpheus.ships.create!(title: "Beat Sheet 3", description: "A rhythm game where every beat is a cell lighting up in time, thrice.",
                                   repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/play",
                                   hours: 4, screenshot: upload, screenshot_shows_game: true)
    third.update_columns(approved_columns(4)) # older data: the model now refuses a total below the earlier approval (D-097)
    assert_equal 10.0, AirtableFields.ship(first)["Optional - Override Hours Spent"]
    row = AirtableFields.ship(second)
    assert_equal 5.0, row["Optional - Override Hours Spent"]
    assert_not row.key?("Optional - Override Hours Spent Justification"), "the separate fields carry it (D-030)"
    assert_match "claims only the 5 hours since then", row["Optional - Override Duplicate Justification"]
    assert_match "10 hours since Save Point began", row["Optional - Override Duplicate Justification"]
    assert_equal 0.0, AirtableFields.ship(third)["Optional - Override Hours Spent"], "never below zero"
  end

  # D-111: a deflation whose cut below the limits has no reason isn't sent. It waits its hour like any row that can't be built, with the
  # error's class in the log and no value, and goes once the reason is there. The database holds the reason of the whole cut, so this
  # takes a ship the limits' own words explain in part: 4 hours claimed, the limits cut 1 of AI coding, the reviewer took 1 more.
  test "a ship deflated below the limits with no reason waits, is logged by class, and goes when it has its reason (D-111)" do
    ship = approved_ship(approved_hours: 10)
    ship.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 0)
    limits_say = ship.limits(10).reason
    # the limits' words and none of the reviewer's
    ship.update_columns(claimed_hours: 10, review_hours: 5, approved_hours: 5, review_coding_hours: 5, review_art_hours: 0, deflation_reason: limits_say)
    other = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.", repo_url: "https://github.com/ana/pong",
                                         demo_url: "https://example.com/pong", hours: 3, screenshot: upload, screenshot_shows_game: true)
    other.update_columns(approved_columns(3))
    io = StringIO.new
    old = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    Airtable::SyncJob.perform_now
    Rails.logger = old

    assert_equal [ "ship-#{other.id}" ], @fake.rows(SUBMISSIONS).map { it["save_point_id"] }, "the others go"
    assert_not_nil ship.reload.airtable_failed_at
    assert_nil ship.synced_at
    assert_match "ship-#{ship.id} could not be built, AirtableFields::UnexplainedDeflation", io.string
    assert_no_match(/Orpheus|orpheus@/, io.string)

    ship.update_columns(deflation_reason: "#{limits_say} Half the levels were cut.")
    @fake.upserts.clear
    Airtable::SyncJob.perform_now
    assert_empty @fake.rows(SUBMISSIONS), "it waits its hour"
    travel 61.minutes do
      Airtable::SyncJob.perform_now
    end
    row = @fake.rows(SUBMISSIONS).find { it["save_point_id"] == "ship-#{ship.id}" }
    assert_match "Half the levels were cut.", row["Justification - Deflation Justification"]
    assert_nil ship.reload.airtable_failed_at
  ensure
    Rails.logger = old if old
  end

  # D-111: a ship corrected to its claimed hours has no deflation sentence now. The upsert leaves out a field with no value, so the sentence
  # the row already holds is cleared with a nil, and only when it is the app's own: words written in Airtable stay.
  test "a corrected ship clears the deflation sentence its row still holds, and leaves words written in Airtable (D-111)" do
    ship = approved_ship(approved_hours: 10)
    deflation = AirtableFields::DEFLATION_FIELD
    @fake.existing = { "ship-#{ship.id}" => { "id" => "rec1", "fields" => { deflation => "Deflated from 10 to 9.99 hours: the reviewer's cut below the limits (-0.01 hrs)." } } }
    Airtable::SyncJob.perform_now
    row = @fake.rows(SUBMISSIONS).sole
    assert row.key?(deflation), "sent as a nil, which clears the cell"
    assert_nil row[deflation]

    ship.update_columns(synced_at: nil)
    @fake.existing = { "ship-#{ship.id}" => { "id" => "rec1", "fields" => { deflation => "Armand's own note on the hours." } } }
    @fake.upserts.clear
    Airtable::SyncJob.perform_now
    assert_not @fake.rows(SUBMISSIONS).sole.key?(deflation), "words written in Airtable stay"

    ship.update_columns(synced_at: nil)
    @fake.existing = {}
    @fake.upserts.clear
    Airtable::SyncJob.perform_now
    assert_not @fake.rows(SUBMISSIONS).sole.key?(deflation), "a first sync has nothing to clear"
  end

  # D-111: the migration puts a corrected ship 50 minutes into the sync's hour of waiting, so the old pods of a rolling deploy leave it
  # alone, and the new code sends it ten minutes on, clearing the sentence its row still holds.
  test "a corrected ship put 50 minutes into its wait goes ten minutes on, and clears the old deflation sentence (D-111)" do
    ship = approved_ship(approved_hours: 10)
    deflation = AirtableFields::DEFLATION_FIELD
    ship.update_columns(synced_at: nil, airtable_failed_at: 50.minutes.ago)
    @fake.existing = { "ship-#{ship.id}" => { "id" => "rec1", "fields" => { deflation => "Deflated from 10 to 9.99 hours." } } }
    Airtable::SyncJob.perform_now
    assert_empty @fake.rows(SUBMISSIONS), "not due yet"
    assert_nil ship.reload.synced_at

    travel 11.minutes do
      Airtable::SyncJob.perform_now
    end
    row = @fake.rows(SUBMISSIONS).sole
    assert row.key?(deflation), "the old sentence is cleared"
    assert_nil row[deflation]
    assert_not_nil ship.reload.synced_at
    assert_nil ship.airtable_failed_at
  end

  test "a ship still deflated sends its sentence over the one its row holds" do
    ship = approved_ship(approved_hours: 10)
    ship.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 0)
    ship.update_columns(claimed_hours: 10, review_hours: 8, approved_hours: 8, review_coding_hours: 8, review_art_hours: 0,
                        deflation_reason: "#{ship.limits(10).reason} A menu was cut.")
    @fake.existing = { "ship-#{ship.id}" => { "id" => "rec1", "fields" => { AirtableFields::DEFLATION_FIELD => "Deflated from 10 to 9.99 hours." } } }
    Airtable::SyncJob.perform_now
    assert_match "Deflated from 10 to 8 hours", @fake.rows(SUBMISSIONS).sole[AirtableFields::DEFLATION_FIELD]
  end

  test "a ship address with two street lines splits them, and the phone never goes" do
    @orpheus.user.update!(address: { "street_address" => "1 Hack Ln\nUnit 2", "locality" => "Shelburne", "country" => "US" }, phone_number: "+18025550123")
    row = AirtableFields.ship(approved_ship)
    assert_equal [ "1 Hack Ln", "Unit 2" ], row.values_at("Address (Line 1)", "Address (Line 2)")
    assert_no_match(/8025550123/, row.to_json)
  end

  test "ship records go to the submission table by its id" do
    approved_ship
    Airtable::SyncJob.perform_now
    assert_includes @fake.upserts.map(&:first), "tblvPYnH7OouAeFkC"
    assert_not_includes @fake.upserts.map(&:first), "YSWS Project Submission"
  end

  test "a failed batch goes row by row, only the rows that went are stamped, and later tables still run" do
    User.create!(hca_id: "ident!bad", email: "bad@example.com")
    bad = User.find_by!(hca_id: "ident!bad")
    @fake.fail_on = [ "user-#{bad.id}" ]
    Airtable::SyncJob.perform_now
    assert_not_nil bad.reload.airtable_failed_at
    assert_nil bad.synced_at, "a failed row is not stamped"
    assert_equal User.count - 1, User.where.not(synced_at: nil).count, "its neighbours went one by one"
    assert_includes @fake.rows("Projects").map { it["save_point_id"] }, "project-#{@orpheus.id}"
    # It waits an hour, then goes again.
    @fake.fail_on = nil
    @fake.upserts.clear
    Airtable::SyncJob.perform_now
    assert_not_includes @fake.rows("Users").map { it["save_point_id"] }, "user-#{bad.id}"
    travel 61.minutes do
      Airtable::SyncJob.perform_now
      assert_includes @fake.rows("Users").map { it["save_point_id"] }, "user-#{bad.id}"
    end
    assert_not_nil bad.reload.synced_at
    assert_nil bad.airtable_failed_at
  end

  test "a whole table that fails does not stop the next one" do
    @fake.fail_table = "Users"
    Airtable::SyncJob.perform_now
    assert_empty @fake.rows("Users")
    assert @fake.rows("Projects").any?
    assert User.where(synced_at: nil).any?
    assert User.where.not(airtable_failed_at: nil).any?
  end

  test "the log holds a row id and an error type, never a value" do
    @fake.fail_table = "Users"
    io = StringIO.new
    old = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    Airtable::SyncJob.perform_now
    assert_match "INVALID_VALUE_FOR_COLUMN", io.string
    assert_no_match(/orpheus@hackclub\.com/, io.string)
  ensure
    Rails.logger = old
  end

  test "a row that changed while its batch was in flight is not stamped" do
    user = @orpheus.user
    fake = @fake
    fake.define_singleton_method(:upsert) do |table, rows, merge_on:|
      User.find(user.id).update!(first_name: "Changed") if table == "Users"
      super(table, rows, merge_on:)
    end
    Airtable::SyncJob.perform_now
    assert_nil user.reload.synced_at, "the change goes next time"
    assert_not_nil User.where.not(id: user.id).first.synced_at
  end

  test "a change to a synced column sends the row next; an untouched column does not" do
    Airtable::SyncJob.perform_now
    user = @orpheus.user.reload
    assert_not_nil user.synced_at
    user.update!(slack_muted_at: Time.current)
    assert_not_nil user.reload.synced_at
    user.update!(first_name: "Orph")
    assert_nil user.reload.synced_at
  end

  test "approving a ship and buying a prize send the project again, for its hours" do
    Airtable::SyncJob.perform_now
    assert_not_nil @orpheus.reload.synced_at
    approved_ship
    assert_nil @orpheus.reload.synced_at
  end

  test "takes the stalest ten rows of a table, never-synced first" do
    12.times { |i| User.create!(hca_id: "ident!bulk#{i}", email: "b#{i}@example.com") }
    Airtable::SyncJob.perform_now
    assert_equal 10, @fake.rows("Users").size
    assert_equal User.count - 10, User.where(synced_at: nil).count
  end

  test "does nothing while disabled" do
    @config[:enabled] = false
    Airtable::SyncJob.perform_now
    assert_empty @fake.upserts
  end
end
