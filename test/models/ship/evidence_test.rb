require "test_helper"

class Ship::EvidenceTest < ActiveSupport::TestCase
  setup do
    @project = projects(:orpheus)
    @user = @project.user
    link_hackatime(@user)
    @project.update!(hackatime_projects: [ "Gloobls", "Halloween Game" ], repo_url: "https://github.com/orpheus/beat-sheet")
    @ship = @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                   repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat", hours: 7,
                                   hackatime_projects: [ "Gloobls", "Halloween Game" ], screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                                   screenshot_shows_game: true)
    @ship.update_columns(created_at: Program::STARTS_AT + 1.day)
    @stardance_token = ENV["STARDANCE_MCP_TOKEN"]
  end

  teardown do
    ENV["STARDANCE_MCP_TOKEN"] = @stardance_token
    Web.adapter = nil
    restore_project_seconds
  end

  # Hackatime's per-project seconds are { name => seconds } for the end of the range: 3 hours up to the ship, 5 now.
  def hackatime_says(at_ship: { "Gloobls" => 3600, "Halloween Game" => 7200 }, now: { "Gloobls" => 7200, "Halloween Game" => 10_800 })
    @original ||= Hackatime.method(:project_seconds)
    Hackatime.define_singleton_method(:project_seconds) do |_user, _names, times|
      answer = times.end > Time.current - 1.minute ? now : at_ship
      raise Hackatime::Unavailable, "down" if answer == :down

      answer
    end
  end

  def restore_project_seconds
    Hackatime.define_singleton_method(:project_seconds, @original) if @original
  end

  def rows(evidence) = evidence.hackatime.rows.map { [ it.name, it.at_ship, it.now ] }

  test "the breakdown kept at ship time sits beside the live figures" do
    @ship.update!(hackatime_seconds: { "Gloobls" => 1800, "Halloween Game" => 3600 })
    hackatime_says
    evidence = Ship::Evidence.new(@ship)

    assert evidence.hackatime.captured
    assert_equal [ [ "Gloobls", 1800, 7200 ], [ "Halloween Game", 3600, 10_800 ] ], rows(evidence)
    assert_nil evidence.hackatime.problem
  end

  test "an older ship with no breakdown shows live figures up to the ship, and says so" do
    hackatime_says
    evidence = Ship::Evidence.new(@ship.tap { |ship| assert_nil ship.hackatime_seconds })

    assert_not evidence.hackatime.captured
    assert_equal [ [ "Gloobls", 3600, 7200 ], [ "Halloween Game", 7200, 10_800 ] ], rows(evidence)
  end

  test "when Hackatime is down the rows keep what is stored and a problem line says the rest is missing" do
    @ship.update!(hackatime_seconds: { "Gloobls" => 1800, "Halloween Game" => 3600 })
    hackatime_says(now: :down)
    evidence = Ship::Evidence.new(@ship)

    assert_equal [ [ "Gloobls", 1800, nil ], [ "Halloween Game", 3600, nil ] ], rows(evidence)
    assert_match(/couldn't be reached/, evidence.hackatime.problem)
  end

  test "without Hackatime linked there is nothing live to show" do
    @user.update!(hackatime_uid: nil, hackatime_access_token: nil)
    assert_match(/haven't linked Hackatime/, Ship::Evidence.new(@ship).hackatime.problem)
  end

  test "a release from before Save Point began is flagged, and so is one older than the first commit since" do
    Web.adapter = lambda do |_method, url, _headers|
      body = case URI(url).path
      when "/repos/orpheus/beat-sheet" then { full_name: "orpheus/beat-sheet", pushed_at: "2026-10-24T00:00:00Z", stargazers_count: 0 }
      when "/repos/orpheus/beat-sheet/releases/latest" then { tag_name: "v0.1", html_url: "https://github.com/orpheus/beat-sheet/releases/tag/v0.1", published_at: "2026-10-10T00:00:00Z", assets: [] }
      else []
      end
      Web::Response.new(status: 200, headers: {}, body: body.to_json)
    end

    assert Ship::Evidence.new(@ship).release_predates?

    commits = Ship::Commits::Result.new(status: :ok, commits: [], message: nil, more: false)
    assert Ship::Evidence.new(@ship, commits:).release_predates?
  end

  test "another account with the same repository, or the same Slack account, is listed" do
    other = users(:ana)
    projects(:ana).update_columns(repo_url: "https://www.github.com/Orpheus/Beat-Sheet.git")
    other.update_columns(slack_id: @user.slack_id)
    evidence = Ship::Evidence.new(@ship)

    assert_equal [ [ other, "same repository" ] ], evidence.same_repo.map { [ it.user, it.reason ] }
    assert_equal [ [ other, "same Slack account" ] ], evidence.same_person.map { [ it.user, it.reason ] }
    assert_equal 2, evidence.duplicates.size
  end

  test "a repository of their own, alone, warns of nothing" do
    assert_empty Ship::Evidence.new(@ship).duplicates
  end

  test "the Telescreen link opens their Hackatime workbench with the ship's projects, and the bare workbench without an id" do
    @ship.update_columns(hackatime_projects: [ "Slime Survivors", "Jame Gam Game Jam" ])
    assert_equal "https://telescreen.hackclub.com/workbench/hackatime/overview?u=1001&p=Slime+Survivors,Jame+Gam+Game+Jam", Ship::Evidence.new(@ship.reload).telescreen_url
    @ship.update_columns(hackatime_projects: [])
    assert_equal "https://telescreen.hackclub.com/workbench/hackatime/overview?u=1001", Ship::Evidence.new(@ship.reload).telescreen_url
    @user.update_columns(hackatime_uid: nil)
    assert_equal "https://telescreen.hackclub.com/workbench/hackatime/overview", Ship::Evidence.new(@ship.reload).telescreen_url
    @user.update_columns(hackatime_uid: "fake-fresh-1")
    assert_equal "https://telescreen.hackclub.com/workbench/hackatime/overview", Ship::Evidence.new(@ship.reload).telescreen_url
  end

  test "the Lapse review link carries their Hackatime id when there is one" do
    assert_equal "https://telescreen.hackclub.com/workbench/lapse?u=1001", Ship::Evidence.new(@ship).lapse_review_url
    @user.update_columns(hackatime_uid: nil)
    assert_equal "https://telescreen.hackclub.com/workbench/lapse", Ship::Evidence.new(@ship.reload).lapse_review_url
  end

  test "the trust level is the one stored, and asked once when none is" do
    Hackatime.stubbed_trust_levels = { "1001" => "yellow" }
    assert_equal "yellow", Ship::Evidence.new(@ship).trust_level
    assert_equal "yellow", @user.reload.hackatime_trust_level

    Hackatime.stubbed_trust_levels = { "1001" => :unavailable }
    @user.update_columns(hackatime_trust_level: nil)
    assert_nil Ship::Evidence.new(@ship).trust_level
  ensure
    Hackatime.stubbed_trust_levels = {}
  end

  test "the Stardance answer reaches the predicate part of the verdict reads" do
    ENV["STARDANCE_MCP_TOKEN"] = nil
    evidence = Ship::Evidence.new(@ship)
    assert evidence.stardance.unknown?
    assert_not evidence.stardance_shipped?
  end
end
