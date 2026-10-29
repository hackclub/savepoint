require "test_helper"

class Admin::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @ana = projects(:ana)
    @ana.user.update!(hackatime_uid: "2002", hackatime_access_token: "token-ana")
    @ana.update!(hackatime_projects: [ "pong" ], repo_url: "https://github.com/ana/pong")
    @ana.user.streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: 2 * 3600)
    @ana.user.streak_activities.create!(activity_date: Program::DATES.begin + 1, coded_seconds: 10 * 60)
    @ana.user.update!(current_streak: 1, timezone: "Europe/Lisbon")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see every project, search them, and open one in full" do
    travel_to Time.utc(2026, 10, 25, 12)
    sign_in_as(users(:orpheus))
    get admin_projects_path

    assert_response :success
    assert_select ".pg-admin-projects__count", "2 projects"
    assert_select ".admin__nav a[aria-current=page]", "Projects"
    assert_select "tr##{dom_id(@ana)}", text: /pong.*pong.*Ana Lovelace.*ana@hackclub\.com.*pong.*2\.2.*1/m
    assert_select "tr##{dom_id(@ana)} a[href=?]", admin_project_path(@ana), "pong"
    assert_select "tr##{dom_id(projects(:orpheus))}", text: /a rhythm game.*not linked.*0.*—/m

    get admin_projects_path(q: "pixelana")
    assert_select "tr##{dom_id(@ana)}"
    assert_select "tr##{dom_id(projects(:orpheus))}", 0
    get admin_projects_path(q: "rhythm")
    assert_select "tr##{dom_id(projects(:orpheus))}"
    assert_select "tr##{dom_id(@ana)}", 0
    get admin_projects_path(q: "nobody at all")
    assert_select ".pg-admin-projects__empty", "No projects match that."

    get admin_project_path(@ana)
    assert_response :success
    assert_select "h1", "pong"
    assert_select ".leaderboard__note", /By\s+Ana Lovelace \(ana@hackclub\.com, pixelana on Slack\), signed Sep 30, in Europe\/Lisbon/m
    assert_select ".admin__tile", text: /Hours\s*2\.2\s*2\.2 of [\d.]+ hrs/m
    assert_select ".admin__tile", text: /Streak\s*1\s*2 days built/m
    assert_select ".admin__tile", text: /Ship\s*Not yet\s*can ship/m
    assert_select ".admin__ship-details", /pong.*Hackatime.*pong/m
    assert_select ".admin__ship-details a[href='https://github.com/ana/pong']"
    assert_select ".admin__table--days tr", text: /Oct 23\s*2\s*counts for the streak/m
    assert_select ".admin__table--days tr", text: /Oct 24\s*0\.2\s*under 20 minutes/m
    assert_select "#admin-project-ships + p", "Not shipped yet."
    assert_select "form[action=?]", admin_user_impersonation_path(@ana.user)
  end

  # D-114: four projects whose columns all differ, made newest last. Ana tracks 2.17 hrs (streak 1), Bo tracks 5 (streak 4, paired
  # with Ana, ship in review), Cy has Hackatime linked with no project (streak 2, invited a buddy, ship sent back), Orpheus nothing.
  def crowd
    now = Time.utc(2026, 10, 25, 12)
    projects(:orpheus).update_columns(created_at: now - 4.days)
    @ana.update_columns(created_at: now - 3.days)
    bo = new_participant("bo", name: "Bo Zed", prize: "aseprite", projects: [ "zeta-game" ], streak: 4, hours: 5)
    bo.update_columns(created_at: now - 2.days, name: "zeta")
    cy = new_participant("cy", name: "Cy Young", prize: "steam25", projects: [], streak: 2, hours: 0)
    cy.update_columns(created_at: now - 1.day)
    cy.update!(buddy_invited: true)
    @ana.pair_with(bo)
    ship_for(bo)
    ship_for(cy).update_columns(status: "changes_needed")
    { orpheus: projects(:orpheus), ana: @ana, bo:, cy: }
  end

  def new_participant(handle, name:, prize:, projects:, streak:, hours:)
    user = User.create!(hca_id: "ident!#{handle}", name:, first_name: name.split.first, email: "#{handle}@hackclub.com", slack_display_name: handle,
                        hackatime_uid: (3000 + handle.sum).to_s, hackatime_access_token: "token-#{handle}", current_streak: streak)
    project = Project.create!(user:, idea: "idea of #{handle}", prize_key: prize, pace_minutes: 45, build_time: "evening", signed_on: "2026-09-30", hackatime_projects: projects)
    user.streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: (hours * 3600).to_i) if hours.positive?
    project
  end

  def ship_for(project)
    project.ships.create!(title: "Ship of #{project.idea}", description: "Two paddles, one ball, and every frame is a sprite.", repo_url: "https://github.com/x/y",
                          demo_url: "https://example.com/x", hours: 1, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                          screenshot_shows_game: true)
  end

  def listed(**params)
    get admin_projects_path(**params)
    assert_response :success
    css_select("tbody tr").map { |row| row["id"] }
  end

  test "D-114: sorts by every column, both ways, the newest first among equals" do
    sign_in_as(users(:orpheus))
    crowd => { orpheus:, ana:, bo:, cy: }
    ids = ->(*list) { list.map { dom_id(it) } }

    assert_equal ids.(cy, bo, ana, orpheus), listed, "default order is newest first"
    assert_equal ids.(cy, bo, ana, orpheus), listed(sort: "nonsense", dir: "up"), "an unknown key is the default"
    assert_select "th[aria-sort]", 0

    prize_order = [ orpheus, ana, bo, cy ].sort_by { |project| Prize::ALL.index { it.key == project.prize_key } }
    {
      "project" => [ ids.(orpheus, cy, ana, bo), ids.(bo, ana, cy, orpheus) ],
      "who" => [ ids.(ana, bo, cy, orpheus), ids.(orpheus, cy, bo, ana) ],
      "pledge" => [ ids.(*prize_order), ids.(*prize_order.reverse) ],
      "hackatime" => [ ids.(orpheus, cy, bo, ana), ids.(bo, ana, cy, orpheus) ],
      "hours" => [ ids.(cy, orpheus, ana, bo), ids.(bo, ana, cy, orpheus) ],
      "streak" => [ ids.(orpheus, ana, cy, bo), ids.(bo, cy, ana, orpheus) ],
      "buddy" => [ ids.(orpheus, cy, bo, ana), ids.(bo, ana, cy, orpheus) ],
      "ship" => [ ids.(ana, orpheus, cy, bo), ids.(bo, cy, ana, orpheus) ]
    }.each do |key, (ascending, descending)|
      assert_equal ascending, listed(sort: key, dir: "asc"), "#{key} ascending"
      assert_equal descending, listed(sort: key, dir: "desc"), "#{key} descending"
    end
    assert_equal ids.(bo, ana, cy, orpheus), listed(sort: "hours"), "hours opens with the most first"
    assert_equal ids.(ana, bo, cy, orpheus), listed(sort: "who"), "a name opens A to Z"
  end

  # D-121: this game's jame gam submissions only. Ana has 2 here, 1 rejected; Bo 3, none flagged; Cy 1, rejected; Orpheus none.
  def jame_gam_crowd
    crowd => { orpheus:, ana:, bo:, cy: }
    entry = ->(id, status, matches, at: "2026-10-25T10:00:00Z") { { "id" => id, "jam" => "Jam 3", "game_title" => "Pong", "review_status" => status, "submitted_at" => at, "matches" => matches } }
    ana.update_columns(jame_gam_checked_at: Time.current, jame_gam_match_count: 2, jame_gam_flagged_match_count: 1, jame_gam_submission_id: "a1",
                       jame_gam_submissions: [ entry.("a1", "Rejected", true), entry.("a2", "Approved", true, at: "2026-10-20T10:00:00Z"), entry.("a3", "Rejected", false) ])
    bo.update_columns(jame_gam_checked_at: Time.current, jame_gam_match_count: 3, jame_gam_submissions: [ entry.("b1", "Pending", true), entry.("b2", "Pending", true), entry.("b3", "Approved", true) ])
    cy.update_columns(jame_gam_checked_at: Time.current, jame_gam_match_count: 1, jame_gam_flagged_match_count: 1, jame_gam_submissions: [ entry.("c1", "Flagged", true) ])
    { orpheus:, ana:, bo:, cy: }
  end

  test "D-121: the jame gam column shows this game's flags, and sorts by them before the limit" do
    sign_in_as(users(:orpheus))
    jame_gam_crowd => { orpheus:, ana:, bo:, cy: }
    ids = ->(*list) { list.map { dom_id(it) } }

    assert_equal ids.(ana, cy, bo, orpheus), listed(sort: "jame_gam"), "most flagged first, then most submissions, then newest"
    assert_equal ids.(ana, cy, bo, orpheus), listed(sort: "jame_gam", dir: "desc")
    assert_equal ids.(orpheus, bo, cy, ana), listed(sort: "jame_gam", dir: "asc")
    get admin_projects_path(sort: "jame_gam")
    assert_select "thead th[aria-sort=descending] a[data-sort=jame_gam]", "Jame gam"
    assert_select "tr##{dom_id(ana)} td[data-label='Jame gam']", text: "Rejected of 2"
    assert_select "tr##{dom_id(ana)} td[data-label='Jame gam'] .pg-admin-projects__jame--flagged", "Rejected"
    assert_select "tr##{dom_id(cy)} td[data-label='Jame gam']", text: "Flagged of 1"
    assert_select "tr##{dom_id(bo)} td[data-label='Jame gam']", text: "3, none flagged"
    assert_select "tr##{dom_id(bo)} td[data-label='Jame gam'] .pg-admin-projects__jame--flagged", 0
    assert_select "tr##{dom_id(orpheus)} td[data-label='Jame gam']", text: "—"

    original = Admin::ProjectsController::LIMIT
    silence_warnings { Admin::ProjectsController.const_set(:LIMIT, 1) }
    assert_equal ids.(ana), listed(sort: "jame_gam")
  ensure
    silence_warnings { Admin::ProjectsController.const_set(:LIMIT, original) } if original
  end

  test "D-121: two flagged submissions show as a count, and the project page lists this game's first, then the other games" do
    sign_in_as(users(:orpheus))
    jame_gam_crowd => { ana: }
    ana.update_columns(jame_gam_flagged_match_count: 2)
    get admin_projects_path
    assert_select "tr##{dom_id(ana)} .pg-admin-projects__jame--flagged", "2 flagged"

    get admin_project_path(ana)
    assert_select "#admin-project-jamegam-mine tbody tr", 2
    assert_select "#admin-project-jamegam-mine tr[data-status=flagged] .ap__jame-status--flagged", "Rejected"
    assert_select "#admin-project-jamegam-mine tbody tr:first-child", text: /Jam 3\s+Pong\s+Rejected\s+Oct 25/
    assert_select "#admin-project-jamegam-others-title", "Other jame gam games"
    assert_select "#admin-project-jamegam-others tbody tr", 1

    ana.update_columns(jame_gam_checked_at: nil, jame_gam_submissions: [])
    get admin_project_path(ana)
    assert_select "#admin-project-jamegam + p, #admin-project-jamegam ~ p", text: "Jame gam not checked yet."
    assert_select "#admin-project-jamegam-others-title", 0
  end

  test "D-114: the current sort shows on its heading, and a second click reverses it" do
    sign_in_as(users(:orpheus))
    crowd
    get admin_projects_path(sort: "hours", dir: "desc", q: "zed")
    assert_select "thead th[aria-sort]", 1
    assert_select "thead th[aria-sort=descending] a[data-sort=hours][href=?]", admin_projects_path(q: "zed", sort: "hours", dir: "asc")
    assert_select "thead th[aria-sort=descending] .pg-admin-projects__sort-arrow"
    assert_select "thead th a[data-sort=who][href=?]", admin_projects_path(q: "zed", sort: "who", dir: "asc"), "Who"
    assert_select "thead th a[data-sort=streak][href=?]", admin_projects_path(q: "zed", sort: "streak", dir: "desc")
    assert_select "form.pg-admin-projects__search input[name=sort][value=hours]"
    assert_select "form.pg-admin-projects__search input[name=dir][value=desc]"

    get admin_projects_path(sort: "who", dir: "asc")
    assert_select "thead th[aria-sort=ascending] a[data-sort=who][href=?]", admin_projects_path(sort: "who", dir: "desc")
    get admin_projects_path
    assert_select "form.pg-admin-projects__search input[name=sort]", 0
    assert_select "thead th a[data-sort=hours][href=?]", admin_projects_path(sort: "hours", dir: "desc")
  end

  test "D-114: the sort covers every matching project before the limit" do
    sign_in_as(users(:orpheus))
    crowd => { bo:, ana: }
    original = Admin::ProjectsController::LIMIT
    silence_warnings { Admin::ProjectsController.const_set(:LIMIT, 2) }
    assert_equal [ dom_id(bo), dom_id(ana) ], listed(sort: "hours", dir: "desc"), "Bo and Ana have the most hours, though they are not the two newest"
    assert_select ".pg-admin-projects__count", "4 projects"
    assert_select ".pg-admin-projects__more", /The first 2 of 4/
    get admin_projects_path
    assert_select ".pg-admin-projects__more", /The newest 2 of 4/
  ensure
    silence_warnings { Admin::ProjectsController.const_set(:LIMIT, original) }
  end

  test "D-114: the hackatime names open Telescreen with the stored id, and are plain text without one" do
    sign_in_as(users(:orpheus))
    @ana.update_columns(hackatime_projects: [ "Excuse Me, Pardon Me", "pong" ])
    get admin_projects_path
    url = "https://telescreen.hackclub.com/workbench/hackatime/overview?u=2002&p=Excuse+Me%2C+Pardon+Me,pong"
    assert_select "tr##{dom_id(@ana)} a#project_#{@ana.id}-telescreen[href=?][target=_blank][rel=noopener]", url, text: "Excuse Me, Pardon Me, pong"
    assert_equal url, Ship::Evidence.new(@ana.ships.build(hackatime_projects: @ana.hackatime_projects)).telescreen_url, "the review page opens the same URL"
    assert_select "tr##{dom_id(projects(:orpheus))} a[href*=telescreen]", 0

    @ana.user.update_columns(hackatime_uid: "ana-not-a-number")
    get admin_projects_path
    assert_select "tr##{dom_id(@ana)} a[href*=telescreen]", 0
    assert_select "tr##{dom_id(@ana)}", text: /Excuse Me, Pardon Me, pong/

    @ana.user.update_columns(hackatime_uid: nil)
    get admin_projects_path
    assert_select "tr##{dom_id(@ana)} a[href*=telescreen]", 0
    assert_select "tr##{dom_id(@ana)} .pg-admin-projects__chip", "not linked"
  end

  test "a project's buddy and ships link through" do
    sign_in_as(users(:orpheus))
    @ana.pair_with(projects(:orpheus))
    ship = @ana.ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                              repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong", hours: 2.2,
                              screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)

    get admin_project_path(@ana)
    assert_select ".admin__ship-details a[href=?]", admin_project_path(projects(:orpheus)), "a rhythm game"
    assert_select ".admin__tile a[href=?]", admin_ship_path(ship), "In review"
    assert_select "#admin-project-ships ~ div tr##{dom_id(ship)}", /In review/

    get admin_projects_path
    assert_select "tr##{dom_id(@ana)} a[href=?]", admin_ship_path(ship), "In review"
    assert_select "tr##{dom_id(@ana)} a[href=?]", admin_project_path(projects(:orpheus)), "a rhythm game"

    get admin_ship_path(ship)
    assert_select "#admin-ship-participant a[href=?]", admin_project_path(@ana), "pong" # D-106: the project link sits in the Participant section
  end

  test "D-087: the project and person pages flag a game that shares a repo with another account" do
    dee = dee_sharing_ana_repo
    sign_in_as(users(:orpheus))

    get admin_project_path(@ana)
    assert_select ".admin__ship-details dd", text: /Shares a repo with dee-builds/
    get admin_user_path(@ana.user)
    assert_select ".au__facts dd", text: /Shares a repo with dee-builds/
    get admin_project_path(dee.project)
    assert_select ".admin__ship-details dd", text: /Shares a repo with #{Regexp.escape(@ana.user.public_name)}/
  end

  test "nobody else can see them" do
    get admin_projects_path
    assert_response :not_found
    get admin_project_path(@ana)
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_projects_path
    assert_response :not_found
    get admin_project_path(@ana)
    assert_response :not_found
  end

  private
    def dee_sharing_ana_repo
      dee = User.create!(hca_id: "ident!dee", first_name: "Dee", slack_display_name: "dee-builds")
      Project.create!(user: dee, idea: "martian", prize_key: "micro", pace_minutes: 45, build_time: "evening", signed_on: "2026-09-30", repo_url: projects(:ana).repo_url)
      dee
    end

    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
