require "test_helper"

# The handbook's justification fields on a ship's submission row (D-030), above all the duplicate justification.
class AirtableFieldsTest < ActiveSupport::TestCase
  REPO = "https://github.com/orpheus/beat-sheet"

  setup do
    @project = projects(:orpheus)
    @project.user.update!(hackatime_uid: "1001")
    Ship::EarlierShip.token = "pat-test"
    @unified = []
    unified = -> { @unified }
    Web.adapter = lambda do |_method, url, _headers|
      assert_includes url, Ship::EarlierShip::BASE
      Web::Response.new(status: 200, headers: {}, body: { records: unified.call.map { { "fields" => it } } }.to_json)
    end
  end

  teardown do
    Web.adapter = nil
    Ship::EarlierShip.token = nil
    ENV.delete("APP_URL")
  end

  # An approved ship, shipped `at`, with what the review kept.
  def approved(at:, hours:, claimed: hours, repo: REPO, **review)
    ship = travel_to(at) do
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             repo_url: repo, demo_url: "https://example.com/play", hackatime_projects: [ "rhythm-game", "beat-sheet-art" ],
                             hours: claimed, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                             screenshot_shows_game: true)
    end
    ship.update_columns({ status: "approved", approved_hours: hours, claimed_hours: claimed, technical_features: "A beat grid and a combo meter.",
                          ai_coding_seconds: 0, art_seconds: 0 }.merge(review))
    ship
  end

  def unified_record(program, approved_at, hours, url: "#{REPO}/")
    { "Code URL" => url, "YSWS–Name" => [ program ], "Approved At" => approved_at, "Override Hours Spent" => hours }
  end

  def first_ship = approved(at: Program::STARTS_AT + 2.days, hours: 6)

  test "a first ship fills the separate fields, not the override justification" do
    row = AirtableFields.ship(first_ship)
    assert_equal "rhythm-game 10/23/2026-10/25/2026, beat-sheet-art 10/23/2026-10/25/2026",
                 row["Justification - Hackatime Project Name(s) + Date Range(s)"]
    assert_equal "1001", row["Justification - Submitter Hackatime ID"]
    assert_equal "A beat grid and a combo meter.", row["Justification - Specific Technical Features"]
    assert_equal 6.0, row["Optional - Override Hours Spent"]
    %w[Optional\ -\ Override\ Hours\ Spent\ Justification Justification\ -\ Deflation\ Justification
       Justification\ -\ Additional\ Justification Optional\ -\ Override\ Duplicate\ Justification].each do |field|
      assert_not row.key?(field), "#{field} stays empty"
    end
    assert_empty row.keys - AirtableSchema.field_names(:ships)
  end

  test "Lapse coding is told under Alternate Tracking Method, and is absent at 0 (D-085)" do
    assert_not AirtableFields.ship(first_ship).key?("Justification - Alternate Tracking Method")
    ship = approved(at: Program::STARTS_AT + 2.days, hours: 6, lapse_coding_hours: BigDecimal("2.5"))
    assert_equal "2.5 hours of Lapse recordings were coding in an editor Hackatime can't track. " \
                 "The reviewer counted them as coding, not art, so they sit outside the 30% art cap.",
                 AirtableFields.ship(ship)["Justification - Alternate Tracking Method"]
    assert_includes AirtableSchema.field_names(:ships), "Justification - Alternate Tracking Method"
  end

  test "a deflated ship states the hours deflated to, then the reviewer's reason" do
    ship = approved(at: Program::STARTS_AT + 2.days, hours: BigDecimal("5.71"), claimed: 10,
                    deflation_reason: "Hackatime has 3 hrs of AI coding on this game, which counts at a third (1 hr).")
    assert_equal "Deflated from 10 hours to 5.71 hours, Hackatime time since 10/23/2026. " \
                 "Hackatime has 3 hrs of AI coding on this game, which counts at a third (1 hr).",
                 AirtableFields.ship(ship)["Justification - Deflation Justification"]
  end

  test "the additional justification links the review when APP_URL is set, and says when AI coding time was unknown" do
    ship = approved(at: Program::STARTS_AT + 2.days, hours: 6, ai_coding_seconds: nil)
    assert_equal "Hackatime's AI coding time could not be read at review, so no AI coding cut applied.",
                 AirtableFields.ship(ship)["Justification - Additional Justification"]
    ENV["APP_URL"] = "https://savepoint.hackclub.com"
    assert_match %r{Review in Save Point: https://savepoint\.hackclub\.com/admin/ships/#{ship.id}\z},
                 AirtableFields.ship(ship)["Justification - Additional Justification"]
  end

  test "the reviewer's judgement goes into the additional justification" do
    ship = approved(at: Program::STARTS_AT + 2.days, hours: 6)
    ship.update!(review_judgement: "The new level is real work.")
    assert_equal "Reviewer judgement: The new level is real work.", AirtableFields.ship(ship)["Justification - Additional Justification"]
  end

  test "a game continued from a jame gam record names it, and claims only time since Save Point began" do
    @unified = [ unified_record("jame gam", "2026-10-20", 4), unified_record("Save Point", "2026-10-26", 6) ]
    text = AirtableFields.ship(first_ship)["Optional - Override Duplicate Justification"]
    assert_equal "This code URL is already in the Unified YSWS DB: jame gam (approved 10/20/2026, 4 hours). " \
                 "Save Point counts only Hackatime time from 10/23/2026, when this project's hours began counting, so time those records " \
                 "counted before then is not claimed again.", text
  end

  test "a record approved after Save Point began is named as one that may overlap" do
    @unified = [ unified_record("jame gam", "2026-10-20T12:00:00.000Z", 4), unified_record("Sleepover", "2026-10-24", nil) ]
    text = AirtableFields.ship(first_ship)["Optional - Override Duplicate Justification"]
    assert_match "jame gam (approved 10/20/2026, 4 hours); Sleepover (approved 10/24/2026, hours unknown).", text
    assert_match "The Sleepover record was approved on 10/24/2026, after this project's hours began counting, so its time from 10/23/2026 may overlap this record.", text
    assert_no_match "The jame gam record", text
  end

  test "an update names the earlier Save Point ship, starts its dates there, and claims only its new hours" do
    first = first_ship
    second = approved(at: Program::STARTS_AT + 5.days, hours: 15)
    row = AirtableFields.ship(second)
    assert_equal 9.0, row["Optional - Override Hours Spent"]
    assert_equal "rhythm-game 10/25/2026-10/28/2026, beat-sheet-art 10/25/2026-10/28/2026",
                 row["Justification - Hackatime Project Name(s) + Date Range(s)"]
    assert_equal "This updates an earlier Save Point ship of this game (10/25/2026, 6 hours since Save Point began). " \
                 "This record claims only the 9 hours since then, 10/25/2026-10/28/2026.",
                 row["Optional - Override Duplicate Justification"]
    assert_not AirtableFields.ship(first).key?("Optional - Override Duplicate Justification"), "the first ship has nothing before it"
  end

  test "an update with a new code URL is no duplicate, but its hours still start after the earlier ship" do
    first_ship
    row = AirtableFields.ship(approved(at: Program::STARTS_AT + 5.days, hours: 15, repo: "https://github.com/orpheus/beat-sheet-2"))
    assert_not row.key?("Optional - Override Duplicate Justification")
    assert_match "10/25/2026-10/28/2026", row["Justification - Hackatime Project Name(s) + Date Range(s)"]
  end

  test "an update of a jame gam game names both" do
    @unified = [ unified_record("jame gam", "2026-10-20", 4) ]
    first_ship
    text = AirtableFields.ship(approved(at: Program::STARTS_AT + 5.days, hours: 15))["Optional - Override Duplicate Justification"]
    assert_match(/\AThis code URL is already in the Unified YSWS DB: jame gam .* not claimed again\. This updates an earlier Save Point ship .* only the 9 hours since then/, text)
  end

  test "only approved earlier ships count, and the ones after this ship don't" do
    @project.ships.destroy_all
    sent_back = approved(at: Program::STARTS_AT + 1.day, hours: 3)
    sent_back.update_columns(status: "changes_needed", approved_hours: nil)
    ship = approved(at: Program::STARTS_AT + 2.days, hours: 6)
    approved(at: Program::STARTS_AT + 4.days, hours: 8)
    row = AirtableFields.ship(ship)
    assert_not row.key?("Optional - Override Duplicate Justification")
    assert_equal 6.0, row["Optional - Override Hours Spent"]
  end

  test "a ship the Unified YSWS DB can't be asked about doesn't build" do
    ship = first_ship
    Web.adapter = ->(*) { Web::Response.new(status: 429, headers: {}, body: "") }
    assert_raises(AirtableFields::UnifiedUnchecked) { AirtableFields.ship(ship) }
    Ship::EarlierShip.token = nil
    assert_raises(AirtableFields::UnifiedUnchecked) { AirtableFields.ship(ship) }
  end
end
