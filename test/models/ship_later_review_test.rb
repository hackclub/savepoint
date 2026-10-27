require "test_helper"

# D-097: a later ship's review judges only the new hours. The ship keeps cumulative totals, so the shop, hours_approved and
# the Unified sync work unchanged, and the limits are read on the whole project.
class ShipLaterReviewTest < ActiveSupport::TestCase
  setup do
    @project = projects(:orpheus)
    @project.user.update!(hackatime_uid: "1001")
    link_hackatime(@project.user)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
    @reviewer = users(:ana)
    # Earlier approval: 5.71 hrs, 4 coding and 1.71 art, from a ship made two days after the start.
    travel_to(Program::STARTS_AT + 2.days)
    @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
    @first = ship_now(hours: 10)
    @first.update_columns(status: "approved", approved_hours: BigDecimal("5.71"), review_hours: BigDecimal("5.71"),
                          review_coding_hours: 4, review_art_hours: BigDecimal("1.71"))
    travel_to(Program::STARTS_AT + 3.days)
    @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 2.days).to_date, coded_seconds: 10 * 3600)
  end

  teardown do
    Web.adapter = nil
    Ship::EarlierShip.token = nil
  end

  test "the earlier approval is the latest approved ship made before, with its hours split and its date" do
    later = ship_now(hours: 20)
    prior = later.earlier_approval
    assert_equal @first, prior.ship
    assert_equal [ BigDecimal("5.71"), BigDecimal("4"), BigDecimal("1.71") ], [ prior.hours, prior.coding, prior.art ]
    assert_equal @first.created_at.to_date, prior.on
    assert_nil @first.earlier_approval, "a first ship has none"

    @first.update_columns(status: "changes_needed")
    assert_nil later.earlier_approval, "only an approved ship counts"
  end

  test "a later ship approves the earlier hours plus the new ones, and stores the cumulative totals" do
    later = ship_now(hours: 20)
    later.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)

    assert later.decide!("approved", by: @reviewer, coding_hours: "6", art_hours: "1", technical_features: "A boss fight.",
                                     deflation_reason: "Some of it was a menu.")
    later.reload
    assert_equal [ BigDecimal("10"), BigDecimal("2.71"), BigDecimal("12.71") ], [ later.review_coding_hours, later.review_art_hours, later.review_hours ]
    assert_equal 20, later.claimed_hours

    assert later.pass_fraud!(by: @reviewer)
    assert_equal BigDecimal("12.71"), later.reload.approved_hours
    assert_equal 12.71, @project.reload.hours_approved
  end

  test "by default a later ship takes the most the limits allow for the new time, on the whole project" do
    later = ship_now(hours: 20)
    later.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
    # Counted 20, AI 3 and art 4: coding 16, coding cap 14, art up to 4. Earlier used 4 coding and 1.71 art.
    assert later.decide!("approved", by: @reviewer, technical_features: "A boss fight.")
    assert_equal [ BigDecimal("14"), BigDecimal("4"), BigDecimal("18") ], [ later.review_coding_hours, later.review_art_hours, later.review_hours ]
  end

  test "the art cap and the AI cut count the earlier approval, so they can leave little or nothing for the new time" do
    later = ship_now(hours: 20)
    later.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 12 * 3600)
    # Counted 20, AI 3, art 12: coding 8, coding cap 6, art held at 2.57. The earlier 4 coding and 1.71 art leave 2 and 0.86.
    limits = later.limits
    assert_equal BigDecimal("2"), limits.new_coding_top(4)
    assert_equal BigDecimal("0.86"), limits.new_art_top(4, BigDecimal("1.71"), BigDecimal("2"))
    assert later.decide!("approved", by: @reviewer, coding_hours: "99", art_hours: "99", technical_features: "A boss fight.")
    assert_equal [ BigDecimal("6"), BigDecimal("2.57") ], [ later.review_coding_hours, later.review_art_hours ]

    capped = ship_now(hours: 20)
    capped.update_columns(ai_coding_seconds: 18 * 3600, art_seconds: 0)
    # Counted 20, AI 18: the coding cap is 20 - 12 = 8 hrs. Earlier used 4 coding, so the new coding is at most 4.
    assert_equal BigDecimal("4"), capped.limits.new_coding_top(4)
    assert_equal 0, capped.limits.new_coding_top(10), "never below zero"
  end

  test "the approved total can never be below the earlier approval" do
    later = ship_now(hours: 20)
    later.update_columns(ai_coding_seconds: 0, art_seconds: 0, status: "awaiting_fraud")

    later.review_hours = BigDecimal("5")
    assert_not later.valid?
    assert_equal [ "Approved hours can't be below the 5.71 hrs already approved" ], later.errors[:approved_hours]

    later.review_hours = BigDecimal("5.71")
    assert later.valid?

    later.status = "approved"
    later.approved_hours = BigDecimal("3")
    assert_not later.valid?
    later.approved_hours = BigDecimal("5.71")
    assert later.valid?
  end

  test "a fraud deduction comes off the new hours only" do
    later = ship_now(hours: 20)
    later.update_columns(ai_coding_seconds: 0, art_seconds: 0)
    assert later.decide!("approved", by: @reviewer, coding_hours: "2", art_hours: "0", technical_features: "A boss fight.", deflation_reason: "Cut.")
    assert_equal BigDecimal("7.71"), later.review_hours
    assert later.pass_fraud!(by: @reviewer, deduction: "50", notes: "None of it.")
    assert_equal BigDecimal("5.71"), later.reload.approved_hours
  end

  test "a first ship reviews exactly as before" do
    @first.update_columns(status: "in_review", approved_hours: nil, review_hours: nil, review_coding_hours: nil, review_art_hours: nil,
                          ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
    assert_nil @first.earlier_approval
    assert @first.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    assert_equal [ BigDecimal("4"), BigDecimal("1.71"), BigDecimal("5.71") ], [ @first.review_coding_hours, @first.review_art_hours, @first.review_hours ]
  end

  test "Unified's override hours equal the new hours the reviewer approved" do
    Ship::EarlierShip.token = "pat-test"
    Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 200, headers: {}, body: { records: [] }.to_json) }
    later = ship_now(hours: 20)
    later.update_columns(ai_coding_seconds: 3 * 3600, art_seconds: 4 * 3600)
    assert later.decide!("approved", by: @reviewer, coding_hours: "6", art_hours: "1", technical_features: "A boss fight.",
                                     deflation_reason: "Some of it was a menu.")
    assert later.pass_fraud!(by: @reviewer)

    assert_equal 12.71, later.reload.approved_hours.to_f
    assert_equal 7.0, AirtableFields.ship(later)["Optional - Override Hours Spent"], "6 coding and 1 art since the earlier 5.71"
    assert_equal 5.71, AirtableFields.ship(@first)["Optional - Override Hours Spent"]
  end

  test "the commit list can be cut to those after a time without touching the full result the release check reads (D-101)" do
    old = Ship::Commits::Commit.new(sha: "aaaaaaa", message: "Old", author: "Ana", date: 3.days.ago, url: "u")
    new = Ship::Commits::Commit.new(sha: "bbbbbbb", message: "New", author: "Ana", date: 1.hour.ago, url: "u")
    full = Ship::Commits::Result.new(status: :ok, commits: [ new, old ], message: nil, more: false)

    assert_equal [ new ], full.since(1.day.ago).commits
    assert_equal [ new, old ], full.commits, "the full result is unchanged"
    assert_equal old.date, Ship::Evidence.new(@first, commits: full).first_commit_at, "the evidence reads the earliest commit of the full range"
  end

  private
    def ship_now(hours:)
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours:, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
end
