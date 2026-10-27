require "test_helper"

class ShipTest < ActiveSupport::TestCase
  setup do
    @project = projects(:orpheus)
    link_hackatime(@project.user)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
  end

  test "shipping keeps what you submitted, and makes it your project's name and repo" do
    ship = @project.ship!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                          changes_made: "Added a combo meter.", repo_url: "github.com/orpheus/beat-sheet",
                          demo_url: "https://docs.google.com/spreadsheets/d/beat",
                          screenshot: fixture_upload, screenshot_shows_game: "1")

    assert ship.persisted?
    assert ship.in_review?
    assert_equal [ "https://github.com/orpheus/beat-sheet", [ "rhythm-game" ] ], [ ship.repo_url, ship.hackatime_projects ]
    assert ship.screenshot.attached?
    assert_equal [ "Beat Sheet", "https://github.com/orpheus/beat-sheet" ], [ @project.reload.title, @project.repo_url ]
    assert @project.screenshot.attached?, "the screenshot you shipped with is your project's too"
    assert_equal ship, @project.ship_in_review
    assert_not @project.shipped?, "not shipped until it's approved"

    ship.update!(status: "approved")
    assert @project.reload.shipped?
  end

  test "shipping keeps the seconds on each linked Hackatime project, from Save Point's start to the ship (D-063)" do
    with_hackatime_hours(2) do
      ship = @project.ship!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                            changes_made: "Added a combo meter.", repo_url: "github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                            screenshot: fixture_upload, screenshot_shows_game: "1")

      assert_equal({ "rhythm-game" => 7200 }, ship.reload.hackatime_seconds)
    end
  end

  test "the breakdown is left unset when Hackatime can't say, and the ship is still made (D-063)" do
    original = Hackatime.method(:project_seconds)
    Hackatime.define_singleton_method(:project_seconds) { |*| raise Hackatime::Unavailable, "down" }
    ship = @project.ship!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                          changes_made: "Added a combo meter.", repo_url: "github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                          screenshot: fixture_upload, screenshot_shows_game: "1")

    assert ship.persisted?
    assert_nil ship.reload.hackatime_seconds
  ensure
    Hackatime.define_singleton_method(:project_seconds, original)
  end

  test "a ship needs a title, a real description, both links, a screenshot and the check that it's real" do
    ship = @project.ship!(title: " ", description: "too short", changes_made: " ", changes_required: true, repo_url: "", demo_url: "", screenshot_shows_game: "0")

    assert_not ship.persisted?
    assert_equal [ "Set the title", "Make the description 40+ characters", "Say what you changed since last time", "Add a repository link",
                   "Add a playable link", "Set a new screenshot", "Confirm the screenshot shows your game" ],
                 ship.errors.map(&:message)
    assert_nil @project.reload.name
  end

  test "a ship never reuses the screenshot your project already has: every ship needs a new one (D-016)" do
    @project.screenshot.attach(fixture_upload)
    ship = @project.ship!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                          changes_made: "Added a combo meter.", changes_required: true, repo_url: "https://github.com/orpheus/beat-sheet",
                          demo_url: "https://example.com/beat", screenshot_shows_game: "1")

    assert_not ship.persisted?
    assert_includes ship.errors[:screenshot], "Set a new screenshot"
  end

  test "the form refuses a screenshot an earlier ship of the project already used" do
    attributes = { title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                   changes_made: "Added a combo meter.", changes_required: true, repo_url: "https://github.com/orpheus/beat-sheet",
                   demo_url: "https://example.com/beat", screenshot_shows_game: "1" }
    first = @project.ship!(attributes.merge(screenshot: fixture_upload))
    assert first.persisted?
    first.decide!("changes_needed", by: users(:ana), feedback: "Add a README.")

    again = @project.ship!(attributes.merge(screenshot: fixture_upload))
    assert_not again.persisted?
    assert_includes again.errors[:screenshot], "Set a new screenshot: this one was on an earlier ship"
  end

  test "deciding is an admin's call, made once, and the ship that stands is each project's newest" do
    first = ship_now(hours: 3)
    assert_not first.decide!("maybe", by: users(:ana))
    assert first.decide!("changes_needed", by: users(:ana), feedback: "Add a README.")
    assert first.changes_needed?
    assert_equal users(:ana), first.decided_by
    assert_not first.decide!("approved", by: users(:ana)), "decided already"
    assert first.reload.changes_needed?

    second = ship_now(hours: 5)
    assert_equal [ second ], Ship.latest_per_project.to_a
    assert_equal 5, Ship.latest_per_project.sum(:hours)
    assert_equal [ first ], Ship.where(created_at: ..first.created_at).latest_per_project.to_a, "as of a time, the newest then"
  end

  test "approving grants the hours that count to spend, or fewer if the admin says, and the most of any approved ship counts" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 12 * 3600)
      approving_grants_hours
    end
  end

  test "changes needed say what to change: no note, no verdict (D-049)" do
    ship = ship_now(hours: 3)
    assert_not ship.decide!("changes_needed", by: users(:ana), feedback: "  ", judgement: "Looks thin.")
    assert_equal [ "Tell the participant what to change" ], ship.errors[:review_feedback]
    assert ship.reload.in_review?
    assert_nil ship.review_judgement, "nothing saved"

    assert ship.decide!("changes_needed", by: users(:ana), feedback: " Add a README. ", judgement: "Looks thin.")
    assert_equal [ "Add a README.", "Looks thin." ], [ ship.reload.review_feedback, ship.review_judgement ]
  end

  test "approving keeps the reviewer's judgement, and the note is optional" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 4 * 3600)
      ship = ship_now(hours: 4)
      assert approve(ship, technical_features: "A combo meter.", judgement: "Plays well.")
      assert_equal [ "Plays well.", nil ], [ ship.reload.review_judgement, ship.review_feedback ]
      assert_equal({}, ship.review_checklist)
    end
  end

  test "hours from before Save Point began are cut: the default and the most are the hours that count" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT - 1.day).to_date, coded_seconds: 5 * 3600)
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 4 * 3600)
      ship = ship_now(hours: 9)
      assert_equal 4, ship.counted_hours
      approve(ship, coding_hours: "9", technical_features: "A combo meter and beat timing.")
      assert_equal 4, ship.approved_hours, "never more than the hours that count"
      other = ship_now(hours: 9)
      approve(other, technical_features: "A combo meter and beat timing.")
      assert_equal 4, other.approved_hours, "by default, all the hours that count"
    end
  end

  def approving_grants_hours
    assert_equal 0, @project.hours_approved
    first = ship_now(hours: 6)
    approve(first, coding_hours: "99", technical_features: "A combo meter and beat timing.")
    assert_equal 6, first.approved_hours, "never more than it took"
    assert_equal 6, @project.reload.hours_approved

    rejected = ship_now(hours: 9)
    rejected.decide!("changes_needed", by: users(:ana), coding_hours: "9", feedback: "Add a README.")
    assert_nil rejected.approved_hours
    assert_equal 6, @project.reload.hours_approved

    second = ship_now(hours: 11)
    approve(second, coding_hours: "4.5", technical_features: "A combo meter and beat timing.",
                                                         deflation_reason: "Half an hour was a broken build.")
    assert_equal 10.5, second.approved_hours, "the earlier 6 plus 4.5 new hours (D-097)"
    assert_equal 10.5, @project.reload.hours_approved, "each ship's total is cumulative, so the latest is the project's"

    approve(ship_now(hours: 2), coding_hours: "-4", technical_features: "A combo meter and beat timing.", deflation_reason: "None of it shows.")
    assert_equal 10.5, @project.reload.hours_approved
  end

  test "changes needed is its own status, and they can ship again" do
    ship = ship_now(hours: 3)
    assert_not ship.changes_needed?
    ship.decide!("changes_needed", by: users(:ana), feedback: "Add a README.")
    assert ship.changes_needed?
    assert_nil @project.reload.ship_in_review, "they can ship again"
  end

  test "only the ship form requires the statement" do
    ship = @project.ships.build(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                                screenshot: fixture_upload, screenshot_shows_game: true)
    assert ship.valid?
    ship.changes_required = true
    assert_not ship.valid?
  end

  test "hours that count start with Save Point, and never exceed the hours shipped" do
    user = @project.user
    travel_to Program::STARTS_AT + 2.days do
      user.streak_activities.create!(activity_date: (Program::STARTS_AT - 3.days).to_date, coded_seconds: 7200)
      user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 5400)
      assert_equal 1.5, ship_now(hours: 9).counted_hours
      assert_equal 1, ship_now(hours: 1).counted_hours
    end
  end

  test "repo and demo links are http or https only" do
    attributes = { title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                   screenshot: fixture_upload, screenshot_shows_game: true }
    [ "javascript:alert(1)", "javascript://example.com/%0Aalert(1)", "data:text/html,x", "vbscript:x", "ftp://example.com/x" ].each do |url|
      ship = @project.ships.build(attributes.merge(repo_url: url, demo_url: url))
      assert_not ship.valid?, "#{url} should not pass"
      assert_equal %i[repo_url demo_url], ship.errors.attribute_names
    end
  end

  test "approving holds the hours to the handbook's limits, needs the technical features, and a reason below the count (D-030)" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
      ship = ship_now(hours: 10)
      ship.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
      assert_equal BigDecimal("5.71"), ship.limits.most

      assert_not ship.decide!("approved", by: users(:ana))
      assert_equal [ "Name the specific technical features that explain the hours" ], ship.errors.map(&:message),
                   "the AI cut and the art hold need no reason"
      assert ship.reload.in_review?, "nothing saved"

      assert_not ship.decide!("approved", by: users(:ana), coding_hours: "3", technical_features: "A rhythm grid.")
      assert_equal [ "Say why you approve fewer hours than the rules allow" ], ship.errors.map(&:message), "below the AI cap needs a reason"
      assert_not ship.decide!("approved", by: users(:ana), art_hours: "1", technical_features: "A rhythm grid.")
      assert_equal [ "Say why you approve fewer hours than the rules allow" ], ship.errors.map(&:message), "and so does less art than the hold allows"

      assert approve(ship, coding_hours: "9", technical_features: "  A rhythm grid and a combo meter. ",
                          deflation_reason: "AI coding counts at a third, and art at most 30%.")
      ship.reload
      assert_equal BigDecimal("5.71"), ship.approved_hours, "never past the limits, whatever is typed"
      assert_equal 10, ship.claimed_hours, "what counted when it was decided"
      assert_equal "A rhythm grid and a combo meter.", ship.technical_features
      assert_equal [ BigDecimal("4"), BigDecimal("1.71"), BigDecimal("5.71") ], [ ship.review_coding_hours, ship.review_art_hours, ship.review_hours ]
      assert_match(/\AHackatime has 3 hrs of AI coding.*art.*AI coding counts at a third, and art at most 30%\.\z/, ship.deflation_reason,
                   "the limits' own words, then the reviewer's")
    end
  end

  test "the hours that count need no reason, and a reason given then isn't kept" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 4 * 3600)
      ship = ship_now(hours: 4)
      ship.update_columns(ai_coding_seconds: 0, art_seconds: 0)
      assert approve(ship, technical_features: "Beat detection.", deflation_reason: "n/a")
      assert_equal 4, ship.reload.approved_hours
      assert_nil ship.deflation_reason
    end
  end

  test "the checklist defaults decide only what the app knows (D-050)" do
    ship = ship_now(hours: 10)
    entry = ->(approved_at) { Ship::EarlierShip::Entry.new(program: "jame gam", approved_at:, hours: 4, code_url: nil, screenshot_url: nil) }
    result = ->(status, *entries) { Ship::EarlierShip::Result.new(status:, entry: entries.last, message: nil, entries:) }
    unchecked = result.(:not_configured)
    limits = ->(art) { Ship::Limits.new(claimed: 10, ai_coding_seconds: 0, art_seconds: art) }

    defaults = ship.checklist_defaults(earlier: unchecked, limits: limits.(nil))
    assert_equal %w[screenshot], defaults.keys, "no continued, art_cap or not_double when unknown"
    assert_equal true, defaults["screenshot"].first
    assert_empty defaults.keys & %w[runs readme hours_fit]

    assert_equal true, ship.checklist_defaults(earlier: result.(:found, entry.("2026-08-01")), limits: limits.(nil))["continued"].first
    assert_not ship.checklist_defaults(earlier: result.(:none), limits: limits.(nil)).key?("continued"), "an unfinished game cannot be refused (D-035)"

    assert_equal true, ship.checklist_defaults(earlier: unchecked, limits: limits.(2 * 3600))["art_cap"].first
    over = ship.checklist_defaults(earlier: unchecked, limits: limits.(6 * 3600))["art_cap"]
    assert_equal false, over.first
    assert_match(/over the cap/, over.last)

    assert_equal false, ship.checklist_defaults(earlier: result.(:found, entry.((Program::STARTS_AT + 1.day).to_date.to_s)), limits: limits.(nil))["not_double"].first
    assert_equal true, ship.checklist_defaults(earlier: result.(:found, entry.("2020-01-01")), limits: limits.(nil))["not_double"].first
    assert_equal true, ship.checklist_defaults(earlier: result.(:none), limits: limits.(nil))["not_double"].first
  end

  test "a saved tick beats the default, both ways, and unknown ticks are unticked (D-050)" do
    ship = ship_now(hours: 3)
    defaults = { "continued" => [ true, "x" ], "not_double" => [ false, "y" ] }
    assert_equal true, ship.checklist_tick("continued", defaults)
    assert_equal false, ship.checklist_tick("not_double", defaults)
    assert_equal false, ship.checklist_tick("runs", defaults)

    ship.review_checklist = { "continued" => false, "not_double" => true }
    assert_equal false, ship.checklist_tick("continued", defaults)
    assert_equal true, ship.checklist_tick("not_double", defaults)
  end

  test "deciding freezes the defaults under the reviewer's saved ticks (D-050)" do
    defaults = { "continued" => [ true, "x" ], "screenshot" => [ true, "y" ] }
    approved = ship_now(hours: 0)
    approved.update!(review_checklist: { "screenshot" => false, "runs" => true })
    assert approve(approved, technical_features: "Beat detection.", checklist_defaults: defaults)
    assert_equal({ "continued" => true, "screenshot" => false, "runs" => true }, approved.reload.review_checklist)

    rejected = ship_now(hours: 0)
    assert rejected.decide!("changes_needed", by: users(:ana), feedback: "Add a README.", checklist_defaults: defaults)
    assert_equal({ "continued" => true, "screenshot" => true }, rejected.reload.review_checklist)

    refused = ship_now(hours: 0)
    assert_not refused.decide!("approved", by: users(:ana), checklist_defaults: defaults)
    assert_equal({}, refused.reload.review_checklist, "nothing frozen when it is not decided")
  end

  test "changes needed asks for neither" do
    ship = ship_now(hours: 3)
    assert ship.decide!("changes_needed", by: users(:ana), feedback: "Add a README.")
    assert_nil ship.reload.technical_features
  end

  test "the AI coding and art time is asked of Hackatime once, from Save Point's start to the ship, and kept" do
    ship = ship_now(hours: 3)
    ship.update_columns(hackatime_projects: [ "rhythm-game" ])
    Hackatime.stubbed_category_seconds = { "1001" => { "ai coding" => 1800, "designing" => 600 } }
    ship.fetch_hackatime_categories!
    assert_equal [ 1800, 600 ], ship.reload.values_at(:ai_coding_seconds, :art_seconds)
    Hackatime.stubbed_category_seconds = { "1001" => { "ai coding" => 9999 } }
    ship.fetch_hackatime_categories!
    assert_equal 1800, ship.reload.ai_coding_seconds, "kept, not asked again"
  ensure
    Hackatime.stubbed_category_seconds = {}
  end

  test "the Lapse time is kept apart for the reviewer's split (D-085)" do
    ship = ship_now(hours: 3)
    ship.update_columns(hackatime_projects: [ "rhythm-game" ])
    Hackatime.stubbed_category_seconds = { "1001" => { "ai coding" => 0, "designing" => 600, "timelapsing" => 1800 } }
    ship.fetch_hackatime_categories!
    assert_equal [ 2400, 1800 ], ship.reload.values_at(:art_seconds, :lapse_seconds)
  ensure
    Hackatime.stubbed_category_seconds = {}
  end

  test "the reviewer sets Lapse coding hours, never above the Lapse hours" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
      ship = ship_now(hours: 10)
      ship.update_columns(ai_coding_seconds: 0, art_seconds: 2 * 3600, lapse_seconds: 90 * 60)
      assert_equal 0, ship.lapse_coding_hours
      assert ship.set_lapse_coding!("1.25")
      assert_equal BigDecimal("1.25"), ship.reload.lapse_coding_hours
      assert_equal BigDecimal("0.75"), ship.limits.art, "2 of art less 1.25 of Lapse coding"
      assert_not ship.set_lapse_coding!("1.51")
      assert_match "coding can't be more", ship.errors.messages_for(:lapse_coding_hours).first
      assert_not ship.set_lapse_coding!("-1")
      assert_not ship.set_lapse_coding!("abc")
      assert_equal BigDecimal("1.25"), ship.reload.lapse_coding_hours
      assert ship.set_lapse_coding!("1.5"), "all of it"
    end
  end

  test "the reviewer raises the AI coding hours: not below Hackatime's, not above the coding claimed, with a reason (D-102)" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
      ship = ship_now(hours: 10)
      ship.update_columns(ai_coding_seconds: 1800, art_seconds: 2 * 3600)
      assert_equal BigDecimal("0.5"), ship.limits.ai_coding

      assert_not ship.set_reviewer_ai!("0.4", "Looks generated")
      assert_match "Hackatime has 0.5 hrs of AI coding, so it can't be less", ship.errors.messages_for(:reviewer_ai_coding_hours).first
      assert_not ship.set_reviewer_ai!("8.01", "Looks generated")
      assert_match "Only 8 hrs of coding was claimed", ship.errors.messages_for(:reviewer_ai_coding_hours).first
      assert_not ship.set_reviewer_ai!("abc", "x")
      assert_not ship.set_reviewer_ai!("3", " ")
      assert_equal [ "Say what looked AI-generated" ], ship.errors.messages_for(:reviewer_ai_reason)
      assert_nil ship.reload.reviewer_ai_coding_hours

      assert ship.set_reviewer_ai!("3", "The repo is one huge pasted dump")
      ship.reload
      assert_equal [ BigDecimal("3"), "The repo is one huge pasted dump" ], [ ship.reviewer_ai_coding_hours, ship.reviewer_ai_reason ]
      assert_equal 3, ship.limits.ai_coding
      assert_equal BigDecimal("0.5"), ship.limits.hackatime_ai
      assert ship.limits.ai_raised?
      assert_equal 6, ship.limits.coding_cap, "coding 8 less two thirds of 3"

      assert ship.set_reviewer_ai!("8", "All of it")
      assert_equal 8, ship.limits.ai_coding

      assert ship.set_reviewer_ai!("", "")
      ship.reload
      assert_nil ship.reviewer_ai_coding_hours
      assert_nil ship.reviewer_ai_reason
      assert_equal BigDecimal("0.5"), ship.limits.ai_coding, "back to Hackatime's figure"
      assert ship.set_reviewer_ai!("3", "Pasted")
      assert ship.set_reviewer_ai!("0.5", ""), "Hackatime's own figure clears it"
      assert_nil ship.reload.reviewer_ai_coding_hours

      ship.update_columns(status: "awaiting_fraud")
      assert_not ship.set_reviewer_ai!("3", "Pasted")
      assert_match "Only a ship in review", ship.errors.messages_for(:reviewer_ai_coding_hours).first
    end
  end

  test "the limits use the larger of Hackatime's and the reviewer's AI coding hours, and 0 when Hackatime is unknown (D-102)" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
      ship = ship_now(hours: 10)
      ship.update_columns(ai_coding_seconds: nil, art_seconds: 0)
      assert_not ship.limits.ai_known?
      assert ship.set_reviewer_ai!("1.5", "Pasted in")
      assert ship.limits.ai_known?
      assert_equal 9, ship.limits.coding_cap, "10 less two thirds of 1.5"
      ship.update_columns(ai_coding_seconds: 5 * 3600)
      assert_equal 5, ship.limits.ai_coding, "Hackatime's figure is larger"
      assert_not ship.limits.ai_raised?
    end
  end

  test "on a later ship the reviewer's AI figure is the project's and can't go below the earlier approval's (D-102, D-097)" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
      earlier = ship_now(hours: 6)
      earlier.update_columns(status: "approved", approved_hours: 6, review_hours: 6, review_coding_hours: 6, review_art_hours: 0,
                             ai_coding_seconds: 1800, art_seconds: 0, reviewer_ai_coding_hours: 3, reviewer_ai_reason: "Pasted in")
    end
    travel_to(Program::STARTS_AT + 3.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 2.days).to_date, coded_seconds: 4 * 3600)
      ship = ship_now(hours: 10)
      ship.update_columns(ai_coding_seconds: 2400, art_seconds: 0)
      assert_equal 3, ship.limits.ai_coding, "the earlier 3 holds with none of its own"
      assert_not ship.set_reviewer_ai!("2", "Less")
      assert_match "The earlier approval already counted 3 hrs", ship.errors.messages_for(:reviewer_ai_coding_hours).first
      assert ship.set_reviewer_ai!("4", "More pasted code")
      assert_equal 4, ship.limits.ai_coding
      assert ship.set_reviewer_ai!("", "")
      assert_nil ship.reload.reviewer_ai_coding_hours
      assert_equal 3, ship.limits.ai_coding, "clearing goes back to the project's floor"
      assert ship.set_reviewer_ai!("3", ""), "the floor itself needs no reason"
    end
  end

  test "approving a ship with Lapse coding holds art to the cap on the larger coding (D-085)" do
    travel_to(Program::STARTS_AT + 2.days) do
      @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
      ship = ship_now(hours: 10)
      ship.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600, lapse_seconds: 3 * 3600)
      assert_equal BigDecimal("5.71"), ship.limits.most, "before: all the art is under the cap"
      ship.set_lapse_coding!("3")
      assert_equal 8, ship.limits.most
      assert ship.decide!("approved", by: users(:ana), technical_features: "A save file.")
      assert_equal [ 7, 1, 8 ], ship.reload.values_at(:review_coding_hours, :review_art_hours, :review_hours).map(&:to_i)
    end
  end

  test "art is designing plus Lapse (timelapsing), and unknown when either is unknown (D-042)" do
    ship = ship_now(hours: 3)
    ship.update_columns(hackatime_projects: [ "rhythm-game" ])
    Hackatime.stubbed_category_seconds = { "1001" => { "ai coding" => 0, "designing" => 600, "timelapsing" => :unavailable } }
    ship.fetch_hackatime_categories!
    assert_nil ship.reload.art_seconds
  ensure
    Hackatime.stubbed_category_seconds = {}
  end

  test "when Hackatime can't say, the AI coding and art time stays unknown and cuts nothing" do
    ship = ship_now(hours: 3)
    ship.update_columns(hackatime_projects: [ "rhythm-game" ])
    Hackatime.stubbed_category_seconds = { "1001" => { "ai coding" => :unavailable } }
    ship.fetch_hackatime_categories!
    assert_nil ship.reload.ai_coding_seconds
    assert_not ship.limits.known?
  ensure
    Hackatime.stubbed_category_seconds = {}
  end

  test "a screenshot can't be a GIF, and a ship that already has one still decides" do
    ship = @project.ships.build(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                                screenshot: Rack::Test::UploadedFile.new(file_fixture("animated.gif"), "image/gif"), screenshot_shows_game: true)
    assert_not ship.valid?
    assert_equal [ "Set a still screenshot as a PNG, JPEG or WebP, not a GIF" ], ship.errors[:screenshot]
    assert_not_includes Project::SCREENSHOT_TYPES, "image/gif"

    ship.save!(validate: false)
    assert ship.reload.decide!("changes_needed", by: users(:ana), feedback: "Add a README."), "only a new screenshot is checked"
  end

  private
    # A review's approval, then a fraud check that passes: the ship is approved and its hours are spendable.
    def approve(ship, **options)
      ship.decide!("approved", by: users(:ana), **options) && ship.pass_fraud!(by: users(:ana))
    end

    def ship_now(hours:)
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours:, screenshot: fixture_upload, screenshot_shows_game: true)
    end

    def fixture_upload
      Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")
    end
end
