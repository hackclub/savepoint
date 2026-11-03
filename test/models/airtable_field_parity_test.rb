require "test_helper"

# D-144: Save Point copies Playground's Airtable field map, and a value is read from stored data, never made up.
# The fixture holds Playground's field names with the commit they came from. A field Playground writes and Save Point
# does not must be listed below with the reason, so every gap shows in review and in this file.
class AirtableFieldParityTest < ActiveSupport::TestCase
  PLAYGROUND = YAML.load_file(Rails.root.join("test/fixtures/files/playground_airtable_fields.yml"))

  # Playground's name => the name Save Point uses for the same thing.
  RENAMED = { "playground_id" => AirtableSchema::ID_FIELD }.freeze

  # Playground fields Save Point leaves out on purpose, each with its reason. Add a line only after Armand agrees.
  USER_GAPS = {
    "Last Name" => "The Users table has no Last Name column yet. The ship row has it, from users.last_name.",
    "Banned" => "Save Point does not sync a banned flag to its Users table.",
    "Loops - playgroundSignupAt" => "Save Point sends no Loops emails from Airtable.",
    "Loops - playgroundFirstShipAt" => "Save Point sends no Loops emails from Airtable.",
    "Loops - playgroundFirstPetCreatedAt" => "Playground only: Save Point has no pets.",
    "Loops - playgroundNoTimeNudge" => "Save Point sends no Loops emails from Airtable."
  }.freeze

  SHIP_GAPS = {
    "Ship Message URL" => "Playground only: a Playground ship carries a ship message link, Save Point has none.",
    "Optional - Override Hours Spent Justification" => "Left empty on purpose (D-030): the separate Justification fields are filled instead.",
    "Justification - Lapse Links, comma-separated" => "Save Point writes Lapse time in Alternate Tracking Method (D-085), not as a list of links."
  }.freeze

  REPO = "https://github.com/orpheus/beat-sheet"

  setup do
    ENV["APP_URL"] = "https://savepoint.hackclub.com"
    @user = users(:orpheus)
    @user.update!(name: "Orpheus the Dino", first_name: "Orpheus", last_name: "Dinosaur", hackatime_uid: "1001", birthdate: "2010-04-01")
    @user.update!(address: { street_address: "15 Falls Rd", street_address_2: "Unit 4", locality: "Shelburne", region: "VT", postal_code: "05482", country: "US" }.to_json)
    @project = projects(:orpheus)
    Ship::EarlierShip.token = "pat-test"
    Web.adapter = ->(*) { Web::Response.new(status: 200, headers: {}, body: { records: [] }.to_json) }
  end

  teardown do
    ENV.delete("APP_URL")
    Web.adapter = nil
    Ship::EarlierShip.token = nil
  end

  # An approved ship with every field Save Point can fill: an earlier ship of the game, a cut below the claim and Lapse coding.
  def full_ship
    upload = -> { Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png") }
    attrs = { title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.", repo_url: REPO,
              demo_url: "https://example.com/play", hackatime_projects: [ "rhythm-game" ], screenshot: upload.call, screenshot_shows_game: true }
    earlier = travel_to(Program::STARTS_AT + 1.day) { @project.ships.create!(attrs.merge(hours: 3, screenshot: upload.call)) }
    earlier.update_columns(approved_columns(3, claimed_hours: 3, ai_coding_seconds: 0, art_seconds: 0))
    ship = travel_to(Program::STARTS_AT + 3.days) { @project.ships.create!(attrs.merge(hours: 12)) }
    columns = approved_columns(8, claimed_hours: 12, technical_features: "A beat grid and a combo meter.", ai_coding_seconds: 0, art_seconds: 0,
                                  lapse_coding_hours: 1, deflation_reason: Ship::Limits.new(claimed: 12, ai_coding_seconds: 0, art_seconds: 0).reason.presence || "Half the levels were cut.")
    ship.update_columns(columns)
    ship.reload
  end

  def diff(playground_names, ours, gaps)
    wanted = playground_names.map { RENAMED.fetch(it, it) }
    missing = wanted - ours - gaps.keys.map { RENAMED.fetch(it, it) }
    stale = gaps.keys - playground_names
    present = gaps.keys & ours
    [ missing, stale, present ]
  end

  test "the fixture names the Playground commit it was copied from" do
    assert_match(/\A\h{40}\z/, PLAYGROUND["commit"])
  end

  test "every Playground user field is in Save Point's user fields, or listed as a gap with its reason" do
    missing, stale, present = diff(PLAYGROUND["user"], AirtableFields.user(@user).keys, USER_GAPS)
    assert_empty missing, "Playground writes these user fields and Save Point does not. Stop and tell Armand: #{missing.join(", ")}"
    assert_empty stale, "Not Playground user fields any more, drop them from USER_GAPS: #{stale.join(", ")}"
    assert_empty present, "Save Point now writes these, drop them from USER_GAPS: #{present.join(", ")}"
    assert USER_GAPS.values.all?(&:present?)
  end

  test "every Playground ship field is in Save Point's ship fields, or listed as a gap with its reason" do
    row = AirtableFields.ship(full_ship, submit_to_unified: true)
    missing, stale, present = diff(PLAYGROUND["ship"], row.keys, SHIP_GAPS)
    assert_empty missing, "Playground writes these ship fields and Save Point does not. Stop and tell Armand: #{missing.join(", ")}"
    assert_empty stale, "Not Playground ship fields any more, drop them from SHIP_GAPS: #{stale.join(", ")}"
    assert_empty present, "Save Point now writes these, drop them from SHIP_GAPS: #{present.join(", ")}"
    assert SHIP_GAPS.values.all?(&:present?)
  end

  # A value comes from a stored column. These users' full names do not contain the stored last name, or have none stored,
  # so a value cut out of the full name would differ from the column.
  test "the name fields equal the stored columns, never a piece of the full name" do
    ship = full_ship
    row = AirtableFields.ship(ship)
    assert_equal [ @user.first_name, @user.last_name ], row.values_at("First Name", "Last Name")
    assert_equal "Dinosaur", row["Last Name"], "the full name is \"Orpheus the Dino\", so a cut would give \"the Dino\""
    assert_equal @user.first_name, AirtableFields.user(@user)["First Name"]
  end

  test "a user with no stored last name has no Last Name, even when the full name has one" do
    @user.update!(name: "Orpheus the Dino", first_name: "Orpheus", last_name: nil)
    row = AirtableFields.ship(full_ship)
    assert_nil row["Last Name"], "the stored last name is empty, so nothing is sent"
  end

  test "a user with a one-word stored first name keeps it when the full name starts differently" do
    @user.update!(name: "Dr. Orpheus Dino", first_name: "Orpheus", last_name: "Dino")
    row = AirtableFields.ship(full_ship)
    assert_equal %w[Orpheus Dino], row.values_at("First Name", "Last Name")
  end
end
