require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  test "without a project, it's back to onboarding" do
    get project_path
    assert_redirected_to onboarding_path

    sign_in_as(mock_hack_club_auth)
    get project_path
    assert_redirected_to onboarding_path
  end

  test "starting from onboarding makes your project, with Save Point's defaults for what it doesn't ask" do
    sign_in_as(mock_hack_club_auth)

    post project_path, as: :json, params: { project: { name: "Pixel Pirates", repo_url: "https://github.com/heidi/pirates",
                                                       jame_gam: true, prize_key: "u2c" } }

    assert_response :created
    assert_equal project_path, response.parsed_body["location"]
    project = User.find_by!(hca_id: "ident!heidi").project
    assert_equal [ "Pixel Pirates", "https://github.com/heidi/pirates", true, "u2c" ],
                 [ project.title, project.repo_url, project.jame_gam, project.prize_key ]
    assert_equal [ "evening", Date.current ], [ project.build_time, project.signed_on ]
    assert_equal Project.pace_for(Prize.find("u2c")), project.pace_minutes
    assert_not project.repo_later?
  end

  test "starting from onboarding saves the build time you chose, and falls back to evening for a missing or invalid one" do
    sign_in_as(mock_hack_club_auth)
    post project_path, as: :json, params: { project: { name: "Pixel Pirates", prize_key: "u2c", build_time: "late night" } }
    assert_response :created
    assert_equal "late night", User.find_by!(hca_id: "ident!heidi").project.build_time

    User.find_by!(hca_id: "ident!heidi").project.destroy!
    post project_path, as: :json, params: { project: { name: "Pixel Pirates", prize_key: "u2c", build_time: "midnight snack" } }
    assert_response :created
    assert_equal "evening", User.find_by!(hca_id: "ident!heidi").reload.project.build_time
  end

  test "a game without a code link says you'll add it later, and picks a Hackatime project it has" do
    user = users(:orpheus)
    user.project.destroy!
    link_hackatime(user)
    sign_in_as(mock_hack_club_auth(uid: user.hca_id, slack_id: "U0ORPHEUS"))
    name = Hackatime.stubbed_projects["1001"].first.name

    post project_path, as: :json, params: { project: { name: "Pong", prize_key: "aseprite", hackatime_project_names: [ name ] } }

    assert_response :created
    project = user.reload.project
    assert_predicate project, :repo_later?
    assert_equal [ name ], project.hackatime_projects
  end

  test "starting a project can pick a Hackatime project with only earlier time (D-089)" do
    user = users(:orpheus)
    user.project.destroy!
    link_hackatime(user)
    sign_in_as(mock_hack_club_auth(uid: user.hca_id, slack_id: "U0ORPHEUS"))
    before = Hackatime.stubbed_all_projects
    Hackatime.stubbed_all_projects = { "1001" => [ Hackatime::Project.new("old-jam", 11_520), Hackatime::Project.new("rhythm-game", 5400) ] }
    assert_not_includes Hackatime.projects(user).map(&:name), "old-jam"

    post project_path, as: :json, params: { project: { name: "Pong", prize_key: "aseprite", hackatime_project_names: [ "old-jam" ] } }

    assert_response :created
    assert_equal [ "old-jam" ], user.reload.project.hackatime_projects
  ensure
    Hackatime.stubbed_all_projects = before
  end

  test "the project page picks a Hackatime project with only earlier time, as HTML and as JSON (D-089)" do
    link_hackatime(users(:orpheus))
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    before = Hackatime.stubbed_all_projects
    Hackatime.stubbed_all_projects = { "1001" => [ Hackatime::Project.new("old-jam", 11_520), Hackatime::Project.new("rhythm-game", 5400) ] }

    patch project_path, params: { project: { hackatime_project_names: [ "old-jam" ] } }
    assert_redirected_to project_path
    assert_equal [ "old-jam" ], projects(:orpheus).reload.hackatime_projects

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game", "old-jam" ] } }, as: :json
    assert_response :no_content
    assert_equal [ "rhythm-game", "old-jam" ], projects(:orpheus).reload.hackatime_projects
  ensure
    Hackatime.stubbed_all_projects = before
  end

  test "a refused pick on the project page answers JSON with the reasons, for Hackatime missing it and not answering (D-103)" do
    link_hackatime(users(:orpheus))
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch project_path, params: { project: { hackatime_project_names: [ "someone-elses-game" ] } }, as: :json
    assert_response :unprocessable_entity
    assert_equal [ "Hackatime projects don't include someone-elses-game on Hackatime" ], response.parsed_body["errors"]

    projects = Hackatime.method(:projects)
    begin
      Hackatime.define_singleton_method(:projects) { |*, **| raise Hackatime::Unavailable, "down" }
      patch project_path, params: { project: { hackatime_project_names: [ "someone-elses-game" ] } }, as: :json
    ensure
      Hackatime.define_singleton_method(:projects, projects)
    end
    assert_response :unprocessable_entity
    assert_equal [ "Hackatime didn't answer. Try again in a moment." ], response.parsed_body["errors"]
  end

  test "starting a project when Hackatime doesn't answer says so, and starts nothing (D-103)" do
    user = users(:orpheus)
    user.project.destroy!
    link_hackatime(user)
    sign_in_as(mock_hack_club_auth(uid: user.hca_id, slack_id: "U0ORPHEUS"))
    name = Hackatime.stubbed_projects["1001"].first.name

    projects = Hackatime.method(:projects)
    begin
      Hackatime.define_singleton_method(:projects) { |*, **| raise Hackatime::Unavailable, "down" }
      post project_path, as: :json, params: { project: { name: "Pong", prize_key: "aseprite", hackatime_project_names: [ name ] } }
    ensure
      Hackatime.define_singleton_method(:projects, projects)
    end

    assert_response :unprocessable_entity
    assert_equal [ "Hackatime didn't answer. Try again in a moment." ], response.parsed_body["errors"]
    assert_nil user.reload.project
  end

  test "changing your prize, right on your project, keeps everything else" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path(edit: "prize")
    assert_select ".project__prize-option button", count: Prize::ALL.size
    assert_select ".project__prize-option button.is-goal", count: 1
    projects(:orpheus).update!(prize_key: "k2")
    get project_path(edit: "prize")
    assert_select ".project__prize-option button.is-goal", count: 1

    keep = projects(:orpheus).reload.attributes.slice("idea", "pace_minutes", "build_time", "signed_on")
    patch project_path, params: { project: { prize_key: "k2" } }
    assert_redirected_to project_path
    project = projects(:orpheus).reload
    assert_equal "k2", project.prize_key
    assert_equal keep, project.attributes.slice(*keep.keys)
    assert_equal [ "rhythm-game" ], project.hackatime_projects

    patch project_path, params: { project: { prize_key: "switch" } }
    assert_response :unprocessable_entity
    assert_equal "k2", project.reload.prize_key
  end

  test "once you've pledged, going through onboarding again takes you to your project and keeps your pledge" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    assert_no_changes -> { projects(:orpheus).reload.attributes } do
      post project_path, as: :json, params: { project: { name: "A puzzle game", prize_key: "u2c" } }
    end
    assert_response :ok
    assert_equal project_path, response.parsed_body["location"]
  end

  test "starting a project needs someone signed in, and a prize and name that exist" do
    post project_path, as: :json, params: { project: { name: "Pong" } }
    assert_response :unauthorized

    sign_in_as(mock_hack_club_auth)
    post project_path, as: :json, params: { project: { name: "Pong", prize_key: "switch" } }
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Prize key is not included in the list"
  end

  test "your project shows your pledge and what's left to set up" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    travel_to Program::STARTS_AT + 2.days
    get project_path

    assert_response :success
    assert_select "h1 .project__title", "a rhythm game"
    assert_select ".project__meta", /done by Nov 2 · 8BitDo Micro$/
    assert_select ".top-bar__progress", "Day 3 of 10"
    assert_select ".project__day", "Day 3 of 10"
    assert_select ".project__step[data-state=current] .project__step-title", /Link Hackatime/
    assert_select ".project__step[data-state=locked]", /Link your Hackatime project/
    assert_select ".project__setup-count", "1 required step left"
    assert_select ".project__setup .project__steps"
    assert_select ".project__streak", count: 0
  end

  # The free stickers' card (D-051) tops the aside in both of its branches: set up or not.
  test "the stickers card counts down the first hour, before and after setup, with the progress on the linked project" do
    user = users(:orpheus)
    user.update_column(:created_at, Time.utc(2026, 10, 25, 10))
    sign_in_as(mock_hack_club_auth(uid: user.hca_id, slack_id: "U0ORPHEUS"))

    travel_to Time.utc(2026, 10, 25, 10, 20) do
      get project_path
      assert_select ".project__side > .sticker-promise:first-child[data-state=counting]", 1
      assert_select ".sticker-promise__title", "Free stickers"
      assert_select ".sticker-promise [data-controller=countdown][data-countdown-ends-at-value=?]", Time.utc(2026, 10, 25, 11).iso8601
      assert_select ".sticker-promise__count a[href=?]", project_path(step: "hackatime_project"), text: /Link your Hackatime project/
      assert_select ".sticker-promise__progress", 0

      link_hackatime(user)
      user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      spans = Hackatime.stubbed_spans
      Hackatime.stubbed_spans = spans.merge(user.hackatime_uid => [ hackatime_span(Time.utc(2026, 10, 25, 10, 10), 2) ])
      get project_path
      assert_select ".project__side > .sticker-promise:first-child[data-state=counting]", 1
      assert_select ".project__locked", 0, "this is the set up branch"
      assert_select ".sticker-promise__count", "2 of 5 minutes"
      assert_select ".sticker-promise__progress[aria-valuenow=?]", "2"
    ensure
      Hackatime.stubbed_spans = spans if spans
    end
  end

  test "the stickers card is the claim button once earned, a quiet note once claimed, and gone for an old account" do
    user = users(:orpheus)
    user.update_column(:created_at, Time.utc(2026, 10, 25, 10))
    sign_in_as(mock_hack_club_auth(uid: user.hca_id, slack_id: "U0ORPHEUS"))
    user.rewards.create!(key: "stickers")

    travel_to Time.utc(2026, 10, 26) do
      get project_path
      assert_select ".sticker-promise[data-state=earned] .sticker-promise__title", "Stickers are yours!"
      assert_select ".sticker-promise a.sp-btn[href=?]", shop_path(claim: "stickers"), text: /Claim your stickers/

      user.update!(address: HQ_ADDRESS)
      user.project.orders.create!(prize_key: "stickers")
      get project_path
      assert_select ".sticker-promise[data-state=claimed]", /once Hack Club sends them/
      assert_select ".sticker-promise a", 0
      assert_no_match(/shipped/i, css_select(".sticker-promise").text)

      user.update_column(:created_at, Reward::STICKERS_SINCE - 1.day)
      get project_path
      assert_select ".sticker-promise", 0
    end
  end

  # The pomodoro's strip for the free stickers (D-051): the overlay's markup, and what the hours poll tells it.
  def stickers_account(spans: [])
    user = users(:orpheus)
    user.update_column(:created_at, Time.utc(2026, 10, 25, 10))
    link_hackatime(user)
    user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    Hackatime.stubbed_spans = Hackatime.stubbed_spans.merge(user.hackatime_uid => spans)
    sign_in_as(mock_hack_club_auth(uid: user.hca_id, slack_id: "U0ORPHEUS"))
    user
  end

  test "the pomodoro overlay carries the stickers strip while counting or earned, and not once claimed" do
    spans_before = Hackatime.stubbed_spans
    user = stickers_account
    travel_to Time.utc(2026, 10, 25, 10, 20) do
      get project_path
      assert_select ".focus .focus-stickers[data-kind=counting]", 1
      assert_select ".focus .focus-stickers [data-controller=countdown][data-countdown-ends-at-value=?]", Time.utc(2026, 10, 25, 11).iso8601
      assert_select ".focus .focus-stickers__title", /Free stickers: 5 minutes before/
      assert_select ".focus .focus-stickers__view[data-focus-target=stickersEarned][hidden]", 1

      user.rewards.create!(key: "stickers")
      get project_path
      assert_select ".focus .focus-stickers[data-kind=earned]", 1
      assert_select ".focus .focus-stickers__title", "Stickers are yours!"
      assert_select ".focus .focus-stickers a[href=?][target=_blank]", shop_path(claim: "stickers")

      user.update!(address: HQ_ADDRESS)
      user.project.orders.create!(prize_key: "stickers")
      get project_path
      assert_select ".focus .focus-stickers", 0
    end
  ensure
    Hackatime.stubbed_spans = spans_before
  end

  test "the hours poll carries the stickers state while counting, and null for an old account" do
    spans_before = Hackatime.stubbed_spans
    user = stickers_account(spans: [ hackatime_span(Time.utc(2026, 10, 25, 10, 10), 2) ])
    travel_to Time.utc(2026, 10, 25, 10, 20) do
      get hours_project_path(refresh: 1)
      assert_equal({ "kind" => "counting", "minutes" => 2, "percent" => 40, "text" => "2 of 5 minutes" }, response.parsed_body["stickers"])

      user.update_column(:created_at, Reward::STICKERS_SINCE - 1.day)
      get hours_project_path(refresh: 1)
      assert_response :success
      assert_nil response.parsed_body["stickers"]
    end
  ensure
    Hackatime.stubbed_spans = spans_before
  end

  test "the hours poll reports the stickers earned once the synced minutes are enough" do
    spans_before = Hackatime.stubbed_spans
    stickers_account(spans: [ hackatime_span(Time.utc(2026, 10, 25, 10, 10), 6) ])
    travel_to Time.utc(2026, 10, 25, 10, 30) do
      get hours_project_path(refresh: 1)
      assert_equal "earned", response.parsed_body.dig("stickers", "kind")
      assert users(:orpheus).reload.earned?("stickers")
    end
  ensure
    Hackatime.stubbed_spans = spans_before
  end

  test "setup walks you through every step after Hackatime, one at a time, then shows your schedule" do
    projects(:orpheus).update!(prize_key: "steam100") # 17 hours, so the schedule runs past the play party
    with_hackatime_hours(1.5) { setup_walkthrough }
  end

  def setup_walkthrough
    begin
      sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
      mock_hackatime
      post "/auth/hackatime"
      follow_redirect!
      assert projects(:orpheus).set_up?, "linking Hackatime is all setup needs to unlock things"

      get project_path
      assert_select ".project__setup-count", "3 optional steps left"
      assert_select ".project__step[data-state=current] .project__step-title", /Link your Hackatime project/
      assert_no_match(/#wrong\b|Slack channel/, css_select(".project__steps").text, "Slack isn't a setup step")

      patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game" ] } }
      follow_redirect!
      assert_select ".project__step[data-state=current] .project__step-title", /Add your git repo/
      assert_select ".project__note", "Hours count now. A couple of quick things and you're in."
      assert_select ".project__schedule", count: 0

      patch project_path, params: { project: { repo_later: true } }
      follow_redirect!
      assert_select ".project__step[data-state=current] .project__step-title", /Bring a buddy/

      patch project_path, params: { project: { buddy_skipped: true } }
      follow_redirect!
      assert_select ".project__note", count: 0
      assert_select ".project__linked .project__linked-project", "rhythm-game"
      assert_select ".project__setup-summary", "Git repo put off"
      assert_equal [ "1.5 of 17 hrs", "2 hrs", "Oct 31" ], css_select(".project__goal-value").map(&:text)
      assert_equal [ "17 hrs $100 Steam gift card" ], css_select(".project__track-label").map { _1.text.squish }
      assert_select ".project__day-cell[data-state=party]", /Party/
      assert_select ".project__event[data-kind=party]", /Play party.*Friday at 7pm ET · on stream/m
      assert_select ".project__event[data-kind=ship] .project__event-day", "2", "the deadline, not the day your hours would be in"
      assert_select ".project__event[data-kind=ship] .project__event-title", "Deadline"
      assert_select ".project__schedule-note", "8 sessions of 2 hrs gets you there by Oct 31. Ship any time up to Nov 2."
      assert_select ".project__day-cell[data-state=goal]", /Goal/
      assert_select ".project__day-cell[data-state=due] .project__day-date", "2"
      assert_select ".project__day-cell[data-state=some] .project__day-value", "1.5h", "yesterday's 1.5 hours fill its cell"
      assert_select ".project__stair[data-you]", /You/
      assert_select ".project__stairs-note", "Today. You're in first."
      assert_equal [ "Gold star", "Shoutout in Slack" ], css_select(".project__reward-label").map(&:text)
      assert_equal [ "Day 3", "Day 5" ], css_select(".project__reward-day").map(&:text)
      assert_select ".project__track-stop", count: 1
      assert_select ".project__track-disc", count: 0
    end
  end

  test "adding your game to the play party queue" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    patch project_path, params: { project: { party_queued: true } }
    follow_redirect!

    assert_select ".project__party-queued", /In the queue/
    assert_select ".project__event[data-kind=party]", /We'll play your game live/
  end

  test "taking your game out of the play party queue" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true, party_queued: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path
    assert_select ".project__party-queued", /In the queue/
    assert_select "form[action='#{project_path}'] button", text: "Take my game out"
    assert_select "button", text: "Add my game to the queue", count: 0

    patch project_path, params: { project: { party_queued: false } }
    assert_redirected_to project_path
    assert_not projects(:orpheus).reload.party_queued?
    follow_redirect!

    assert_select ".project__party-queued", count: 0
    assert_select "button", text: "Take my game out", count: 0
    assert_select "button", text: "Add my game to the queue"
  end

  test "the Hackatime list shows your Hackatime projects to tick, and only those can be linked" do
    link_hackatime(users(:orpheus))
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path

    assert_select ".hkp__text", "Pick your game, even if you've worked on it before. Only time from Oct 23 on counts."
    assert_equal [ "rhythm-game", "beat-sheet-art", "dotfiles" ], css_select(".hkp__name").map(&:text)
    assert_equal [ "1.5hrs", "0.3hrs", "3.1hrs" ], css_select(".hkp__hours").map { it.text.gsub(/\s+/, "") }
    assert_select ".hkp__input[checked]", count: 0
    assert_select ".hkp .hkp__input:not([name])", 3, "ticks are sent by the picker, not by a form"
    assert_select "button", text: /Save|Pick a project/, count: 0

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game", "dotfiles" ] } }
    follow_redirect!
    assert_equal [ "rhythm-game", "dotfiles" ], projects(:orpheus).reload.hackatime_projects

    get project_path(step: "hackatime_project")
    assert_equal %w[rhythm-game dotfiles], css_select(".hkp__input[checked]").map { |box| box["value"] }

    patch project_path, params: { project: { hackatime_project_names: [ "" ] } }
    assert_response :unprocessable_entity
    assert_select ".project__step-error", /need one picked/

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game", "someone-elses-game" ] } }
    assert_response :unprocessable_entity
    assert_select ".project__step[data-state=current] .project__step-error", /don't include someone-elses-game on Hackatime/
    assert_equal [ "rhythm-game", "dotfiles" ], projects(:orpheus).reload.hackatime_projects
  end

  test "the first new Hackatime project you log time on links itself, until you keep it or change it" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    mock_hackatime
    post "/auth/hackatime"
    follow_redirect!
    assert_equal %w[rhythm-game beat-sheet-art dotfiles], projects(:orpheus).reload.hackatime_baseline

    get project_path
    assert_empty projects(:orpheus).reload.hackatime_projects, "projects you already had don't link themselves"
    assert_select ".project__auto-linked", count: 0
    assert_select ".hkp__status", /The first new project you log time on links itself/

    with_hackatime_projects(Hackatime::Project.new("save-point-game", 120), Hackatime::Project.new("scratch", 0)) do
      get project_path
    end
    project = projects(:orpheus).reload
    assert_equal [ "save-point-game" ], project.hackatime_projects
    assert project.hackatime_auto_linked?
    assert project.step_done?("hackatime_project")
    assert_select ".project__auto-linked-title", "Is save-point-game your game?"
    assert_select ".project__auto-linked button", "Yes"
    assert_select ".project__auto-linked a[href=?]", project_path(step: "hackatime_project"), "Pick another"
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_match(/new time from you on \*save-point-game\*, so it's linked to \*a rhythm game\*/, dm[:args].second)

    patch project_path, params: { project: { hackatime_auto_linked: false } }
    assert_redirected_to project_path
    assert_not projects(:orpheus).reload.hackatime_auto_linked?
    assert_equal [ "save-point-game" ], projects(:orpheus).hackatime_projects
  end

  test "D-091: a hand-picked link that shares nothing with the game is not asked about" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update_columns(hackatime_projects: [ "life-2" ], hackatime_auto_linked: false)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    get project_path
    assert_select ".project__auto-linked", count: 0
  end

  test "D-086: linked to Hackatime with projects on it but none picked, you're asked to pick one" do
    link_hackatime(users(:orpheus))
    users(:orpheus).update!(hackatime_linked_at: 2.hours.ago)
    projects(:orpheus).update_columns(hackatime_projects: [], hackatime_seen_count: 2, hackatime_seen_seconds: 600)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_hackatime_projects(Hackatime::Project.new("save-point-game", 0)) { get project_path }
    assert_select "#project-pick-hackatime-title", "Which Hackatime project is your game?"
    assert_select ".project__auto-linked a[href=?]", project_path(step: "hackatime_project"), "Pick it"

    projects(:orpheus).update_columns(hackatime_projects: [ "rhythm-game" ])
    with_hackatime_projects(Hackatime::Project.new("save-point-game", 0)) { get project_path }
    assert_select "#project-pick-hackatime-title", count: 0
  end

  test "picking your Hackatime projects yourself replaces one that linked itself, and nothing links itself after" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_baseline: [ "rhythm-game", "beat-sheet-art" ], hackatime_projects: [ "dotfiles" ],
                               hackatime_auto_linked: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game" ] } }
    project = projects(:orpheus).reload
    assert_equal [ "rhythm-game" ], project.hackatime_projects
    assert_not project.hackatime_auto_linked?

    with_hackatime_projects(Hackatime::Project.new("save-point-game", 120)) { get project_path }
    assert_equal [ "rhythm-game" ], projects(:orpheus).reload.hackatime_projects
    assert_select ".project__auto-linked", count: 0
  end

  test "with nothing on Hackatime to pick yet, setup goes on without it, and your first project links itself later" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_baseline: [])
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_only_hackatime_projects do
      get project_path
      assert_select ".project__step[data-state=current] .project__step-title", /Add your git repo/
      assert_select ".project__step[data-state=pending] .project__step-title", /Log your first time on Hackatime/
      assert_select ".project__step[data-state=pending] .project__step-note", /it links itself/
      assert_select ".project__step[data-state=pending] .project__step-waiting", /hasn't seen any coding from you yet/
      assert_select ".project__step-waiting a[href=?]", "https://hackatime.hackclub.com/", text: "Set it up in your editor"
      assert_select ".project__setup-count", "2 optional steps left"
      assert_select ".project__note", "Hackatime's linked. Start building and your project links itself once you log time."

      patch project_path, params: { project: { repo_later: true } }
      patch project_path, params: { project: { buddy_skipped: true } }
      follow_redirect!
      assert_select ".project__setup-summary", "Git repo put off"
      assert_select ".project__linked-list", count: 0
      assert_select ".project__linked-none", /Start building and your project links itself once you log time/
      assert_select ".project__linked a", "Pick"
      assert_select ".project__note", count: 0
      assert_select ".project__ship", count: 0
      get project_ship_path
      assert_redirected_to project_path, "nothing to ship hours from yet"

      get project_path(step: "hackatime_project")
      assert_select ".project__step-waiting", /hasn't seen any coding from you yet/
      assert_select ".project__step-hint", "Nothing on Hackatime yet. Only time from Oct 23 on counts."
      assert_select ".project__step-error", count: 0

      get hours_project_path(refresh: 1)
      assert_not response.parsed_body["tracking"]
    end

    with_only_hackatime_projects(Hackatime::Project.new("save-point-game", 120)) do
      get hours_project_path(refresh: 1)
      assert response.parsed_body["tracking"], "the page's watcher learns it linked itself"
    end
    assert_equal [ "save-point-game" ], projects(:orpheus).reload.hackatime_projects
  end

  test "with Hackatime projects to pick, setup isn't through until you pick yours" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path

    assert_select ".project__step[data-state=current] .project__step-title", /Link your Hackatime project/
    assert_select ".hkp__list"
    assert_select ".project__schedule", count: 0
    assert_select ".project__note", "Hackatime's linked. Which project is yours?"

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game" ] } }
    assert_redirected_to project_path
  end

  test "when Hackatime stops accepting your token, you're asked to link it again" do
    users(:orpheus).update!(hackatime_uid: "9999", hackatime_access_token: "revoked")
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path

    assert_select ".project__step-error", /Your Hackatime link expired/
    assert_select "form[action='/auth/hackatime'] button", "Link Hackatime again"
    assert_select ".project__picker", count: 0
  end

  test "your hours come from your linked Hackatime projects, and the pomodoro can ask for them" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game", "dotfiles" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_hackatime_hours(4.6) { get hours_project_path(refresh: 1) }
    assert_response :success
    assert_equal [ 4.6, "4.6 of 6.5 hrs", true ], response.parsed_body.values_at("hours", "label", "tracking")

    # The same day as the span (it starts at the launch, so it ends before 2am), so the sidebar leaderboard's hours today (the viewer's own date, UTC until they say) are those hours.
    travel_to(Time.utc(2026, 10, 23, 23, 30)) { get project_path }
    assert_select ".project__goal-value", "4.6 of 6.5 hrs", "what the refresh synced, without asking Hackatime again"
    assert_select ".project__stair[data-you] .project__stair-hours", "4.6h", "the leaderboard counts the same hours"
    assert_select ".project__length input[checked]" do |inputs|
      assert_equal "25", inputs.first["value"]
    end
    assert_select ".project__start", /Start pomodoro/
  end

  test "linked with no time ever seen, the page waits for your first heartbeat and checks for it" do
    link_hackatime(users(:orpheus))
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_only_hackatime_projects do
      get project_path
      assert_select ".pg-project[data-controller=first-heartbeat][data-first-heartbeat-url-value='#{first_heartbeat_project_path}']"
      assert_select ".project__heartbeat[data-state=waiting] .project__heartbeat-title", "Waiting for your first heartbeat"
      assert_select ".project__heartbeat a[href='https://hackatime.hackclub.com/']", "set up hackatime"
      assert_select ".project__heartbeat-note", /We haven't seen any time tracked yet, have you set up hackatime\?/
      assert_select ".project__heartbeat-status[hidden]", 1, "no checking line while it waits"
      assert_select ".pg-project[data-controller~=hackatime-watch]", count: 0, message: "one poller, not two"

      get first_heartbeat_project_path
      assert_response :success
      assert_equal false, response.parsed_body["arrived"]
    end

    with_hackatime_projects do
      travel 31.seconds do
        get first_heartbeat_project_path
        assert_equal true, response.parsed_body["arrived"]
      end
    end
  end

  test "once Hackatime has seen your time, the page doesn't wait for a heartbeat" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_seen_seconds: 600, hackatime_seen_count: 1)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    get project_path
    assert_select ".project__heartbeat", count: 0
    assert_select "[data-controller~=first-heartbeat]", count: 0
  end

  test "the first-heartbeat check needs a project" do
    get first_heartbeat_project_path
    assert_redirected_to onboarding_path
  end

  test "late in the program the page leads with the minutes left to your prize, and before it keeps today's display" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_hackatime_hours(4.6) { get hours_project_path(refresh: 1) }

    travel_to(Program::GOAL_SALIENCE_STARTS_AT - 1.hour) do
      get project_path
      assert_select ".project__left", count: 0
    end

    travel_to(Program::GOAL_SALIENCE_STARTS_AT + 1.hour) do
      get project_path
      assert_select ".project__left-title", /1 hr 54 min left to your #{projects(:orpheus).prize_name}/ # 1.9 hrs of the 6.5 to go
      assert_select ".project__left-pace", /45 min, this evening/
      assert_select ".project__today-text h2", "Today: 45 min, this evening"
    end
  end

  test "once your prize's hours are in, no minutes are left to lead with" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_hackatime_hours(7) { get hours_project_path(refresh: 1) }

    travel_to(Program::GOAL_SALIENCE_STARTS_AT + 1.hour) do
      get project_path
      assert_select ".project__left", count: 0
    end
  end

  test "a step you can still do opens when you pick it" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path(step: "repo")
    assert_select ".project__step[data-state=current]", /Add your git repo/

    get project_path(step: "hackatime_project")
    assert_select ".project__step[data-state=current]", /Link Hackatime/, "it's locked until Hackatime is linked"
  end

  test "once you're set up, you can change your daily pace" do
    next_step_page(hours: 1.5) do # a pick the days left can still cover at 45 min
      get project_path(edit: "pace")
      assert_select ".project__pace[aria-pressed=true]", "Just enough · 45 min"

      patch project_path, params: { project: { pace_minutes: 120 } }
      follow_redirect!
      assert_select ".project__goal-value", "2 hrs"
    end
  end

  test "once you're set up, you can change when you build" do
    next_step_page(hours: 1.5) do
      get project_path(edit: "pace")
      assert_select ".project__build-times .project__build-time[aria-pressed=true]", /evening/
      assert_select ".project__build-times .project__build-time", 4

      patch project_path, params: { project: { build_time: "weekends" } }
      assert_redirected_to project_path
      assert_equal "weekends", projects(:orpheus).reload.build_time
      follow_redirect!
      assert_select ".project__goal-label", /Session pace/
      assert_select ".project__day-cell", minimum: 1
      assert projects(:orpheus).reload.pace_feasible?(projects(:orpheus).pace_minutes), "an infeasible pace moves to a feasible one"

      patch project_path, params: { project: { build_time: "evening" } }
      assert_equal "evening", projects(:orpheus).reload.build_time
      follow_redirect!
      assert_select ".project__goal-label", /Daily pace/
    end
  end

  test "a build time that isn't one of the four is rejected" do
    next_step_page(hours: 1.5) do
      patch project_path, params: { project: { build_time: "never" } }
      assert_response :unprocessable_entity
      assert_equal "evening", projects(:orpheus).reload.build_time
    end
  end

  test "renaming your project and adding a screenshot" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch project_path, params: { project: { name: "Beat Sheet" } }
    patch project_path, params: { project: { screenshot: fixture_file_upload("screenshot.png", "image/png") } }
    follow_redirect!

    assert_select ".project__title", "Beat Sheet"
    assert_select ".project__shot-image[alt='Screenshot of Beat Sheet']"
    get leaderboard_path
    assert_select "tr[data-you] .leaderboard__shot"
  end

  test "another participant's screenshot, named by its signed id, doesn't attach" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    projects(:ana).screenshot.attach(fixture_file_upload("screenshot.png", "image/png"))
    others = projects(:ana).screenshot.blob
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch project_path, params: { project: { name: "Beat Sheet", screenshot: others.signed_id } }

    assert_not projects(:orpheus).reload.screenshot.attached?
    assert_equal 1, others.reload.attachments.count
    assert_equal "Beat Sheet", projects(:orpheus).name
  end

  test "a screenshot that isn't an image says so" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    patch project_path, params: { project: { screenshot: fixture_file_upload("notes.txt", "text/plain") } }

    assert_response :unprocessable_entity
    assert_select ".project__shot-error", /should be a still PNG, JPEG or WebP, not a GIF/
    assert_select ".project__shot-placeholder", "Add a screenshot"
  end

  test "a repo that isn't a link says so" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    patch project_path, params: { project: { repo_url: "my game" } }

    assert_response :unprocessable_entity
    assert_select ".project__step[data-state=current] .project__step-error", /should be a link/
  end

  # The schedule card's next step towards your prize, by where it stands (ProjectsHelper#project_next_step).
  # The daily pace picker only offers paces that get you your prize by the deadline.
  test "a pace too slow for the days left is disabled with the reason, and can't be saved" do
    next_step_page(hours: 1.5) do
      get project_path(edit: "pace")
      assert_select ".project__pace[disabled]", "20 min"
      assert_select ".project__pace[disabled][title=?]", "Too slow for #{project_date(projects(:orpheus).deadline)}"
      assert_select ".project__pace:not([disabled])", text: "Just enough · 45 min"
      assert_select ".project__paces-note", /Slower paces can't get you the 8BitDo Micro by /

      patch project_path, params: { project: { pace_minutes: 20 } }
      assert_response :unprocessable_entity
      assert_equal 45, projects(:orpheus).reload.pace_minutes
      patch project_path, params: { project: { pace_minutes: 60 } }
      assert_equal 60, projects(:orpheus).reload.pace_minutes
    end
  end

  test "a saved pace that can't make it any more moves to the slowest one that can" do
    projects(:orpheus).update_columns(pace_minutes: 20)
    next_step_page(hours: 1.5) do
      projects(:orpheus).update_columns(pace_minutes: 20)
      get project_path
      assert_equal 45, projects(:orpheus).reload.pace_minutes
      assert_equal "45 min", css_select(".project__goal-value")[1].text
    end
  end

  test "Just enough is the pace that finishes a day before the deadline, and takes the place of an equal preset" do
    next_step_page(hours: 0.5) do # 6 hrs to go over 8 days left: 7 days of 52 min, up to 55
      get project_path(edit: "pace")
      assert_equal [ "20 min", "45 min", "Just enough · 55 min", "1 hr", "2 hrs", "3 hrs" ], css_select(".project__pace").map { _1.text.squish }
      assert_select ".project__pace:not([disabled])", text: "Just enough · 55 min"
      patch project_path, params: { project: { pace_minutes: 55 } }
      assert_equal 55, projects(:orpheus).reload.pace_minutes
      follow_redirect!
      assert_equal "55 min", css_select(".project__goal-value")[1].text
      assert_select ".project__schedule-note", /sessions of 55 min gets you there by/
      patch project_path, params: { project: { pace_minutes: 52 } }
      assert_response :unprocessable_entity, "only presets and multiples of 5"
    end
  end

  test "when Just enough equals a preset, one pill shows, not two" do
    next_step_page(hours: 1.5) do # 5 hrs over 7 days is 45 min
      get project_path(edit: "pace")
      assert_select ".project__pace", text: "Just enough · 45 min", count: 1
      assert_select ".project__pace", text: "45 min", count: 0
    end
  end

  test "a custom pace that's no longer just enough stays as its minutes, and none is offered once the hours are in" do
    next_step_page(hours: 0.5) do
      projects(:orpheus).update_columns(pace_minutes: 50)
      get project_path(edit: "pace")
      assert_select ".project__pace[aria-pressed=true]", "50 min"
      assert_select ".project__pace", text: "Just enough · 55 min"
    end
  end

  test "no Just enough is offered once the hours are in" do
    next_step_page(hours: 7) do
      get project_path(edit: "pace")
      assert_select ".project__pace", text: /Just enough/, count: 0
    end
  end

  test "with the hours in, every pace is fine and there's no note" do
    next_step_page(hours: 7) do
      get project_path(edit: "pace")
      assert_select ".project__pace", 5
      assert_select ".project__pace[disabled]", 0
      assert_select ".project__paces-note", 0
    end
  end

  test "when no pace can make it, it says so, suggests a cheaper prize and leaves them all open" do
    next_step_page(hours: 0.5, day: 9, pick: Prize::ALL.last.key) do
      get project_path(edit: "pace")
      assert_select ".project__pace[disabled]", 0
      assert_select ".project__paces-note", /Even 3 hrs a day can't get you the #{Regexp.escape(Prize::ALL.last.name)} by .* Pick a cheaper prize\./
      assert_select ".project__paces-note a[href=?]", project_path(edit: "prize")
      assert_equal "Too late", css_select(".project__goal-value").last.text
    end
  end

  test "upcoming days show the time they take at your pace, with the goal marked under it" do
    next_step_page(hours: 1.5) do
      assert_select ".project__day-cell[data-state='']", minimum: 1
      assert_equal [ "45m" ], css_select(".project__day-cell[data-state=''] .project__day-value").map(&:text).uniq
      assert_select ".project__day-cell[data-state=goal] .project__day-value", "30m", "the last day is what's left of the 5 hours"
      assert_select ".project__day-cell[data-state=goal] .project__day-note", "Goal"
    end
  end

  test "still building: the schedule note says how long you've got, and there's no next-step button" do
    next_step_page(hours: 1.5) do
      assert_select ".project__next", count: 0
      assert_select ".project__schedule-note", /sessions of 45 min gets you there by/
    end
  end

  test "logged enough but not shipped: it says to ship, with a Ship it button, and Done by reads Reached" do
    next_step_page(hours: 7) do
      assert_select ".project__next[data-state=ship] .project__schedule-note", "You've logged enough for the 8BitDo Micro. Next, ship your game."
      assert_select ".project__next a.sp-btn--gold[href=?]", project_ship_path, text: /Ship it/
      assert_select ".project__schedule-note", text: /gets you there by/, count: 0
      assert_equal [ "Reached" ], css_select(".project__goal-value").map(&:text).last(1)
    end
  end

  test "shipped and in review: it says it's in review and you can claim once approved" do
    ship_for_next_step("in_review")
    next_step_page(hours: 7) do
      assert_select ".project__next[data-state=review] .project__schedule-note", "Your ship's in review. You can claim the 8BitDo Micro once it's approved."
      assert_select ".project__next a", count: 0
    end
  end

  test "changes needed: it says so and links to the ship page" do
    ship_for_next_step("changes_needed")
    next_step_page(hours: 7) do
      assert_select ".project__next[data-state=changes] .project__schedule-note", "Your ship needs changes. Fix them and ship again."
      assert_select ".project__next a[href=?]", project_ship_path, text: /Ship again/
    end
  end

  test "approved and covering your prize: a Claim it button goes to that prize in the shop" do
    ship_for_next_step("approved")
    next_step_page(hours: 7) do
      assert_select ".project__next[data-state=ready] .project__schedule-note", "Approved. Your 8BitDo Micro is ready to claim."
      assert_select ".project__next a.sp-btn--gold[href=?]", shop_path(anchor: "shop-micro"), text: /Claim it/
    end
  end

  test "claimed: it says the prize is in the queue, then ordered" do
    ship_for_next_step("approved")
    order = Order.new(project: projects(:orpheus), prize_key: "micro", hours: 0)
    order.save!(validate: false)
    next_step_page(hours: 7) do
      assert_select ".project__next[data-state=claimed] .project__schedule-note", "You've claimed the 8BitDo Micro. It's in the queue to be ordered."
      assert_select ".project__next a", count: 0
      order.update!(status: "ordered")
      get project_path
      assert_select ".project__next[data-state=claimed] .project__schedule-note", "Your 8BitDo Micro is ordered and on its way."
    end
  end

  private
    include ProjectsHelper

    def sign_in_as(_auth)
      post "/auth/hackclub"
      follow_redirect!
    end

    # As if these were all Orpheus had logged time on on Hackatime.
    def with_only_hackatime_projects(*projects)
      before = Hackatime.stubbed_projects
      Hackatime.stubbed_projects = before.merge("1001" => projects)
      yield
    ensure
      Hackatime.stubbed_projects = before
    end

    # As if Orpheus had logged time on these on Hackatime too.
    def with_hackatime_projects(*added)
      before = Hackatime.stubbed_projects
      Hackatime.stubbed_projects = before.merge("1001" => before.fetch("1001") + added)
      yield
    ensure
      Hackatime.stubbed_projects = before
    end

  test "adding your repo without https:// works, and junk shows the app's own error" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch project_path, params: { project: { repo_url: "junk" } }
    assert_response :unprocessable_content
    assert_select ".project__step-error", /should be a link/
    assert_select "input[name='project[repo_url]'][type=text][inputmode=url]"
    assert_nil projects(:orpheus).reload.repo_url

    [ "github.com/nanomars/spacegame", "https://github.com/nanomars/spacegame" ].each do |typed|
      projects(:orpheus).update!(repo_url: nil)
      patch project_path, params: { project: { repo_url: typed } }
      assert_equal "https://github.com/nanomars/spacegame", projects(:orpheus).reload.repo_url
    end
  end

  test "the setup card hides once setup is finished with nothing put off, and shows what's put off" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    get project_path
    assert_select ".project__setup-done .project__steps"
    assert_select ".project__setup-summary", "Git repo put off"

    projects(:orpheus).update!(repo_url: "https://github.com/orpheus/rhythm-game")
    get project_path
    assert_response :success
    assert_select ".project__setup-done", count: 0 # buddy skipped counts as done
    assert_select ".project__steps", count: 0
    assert_select ".project__linked" # Hours from is still there
    assert_select ".project__linked-panel[hidden] .hkp", 1 # its tick list is there, closed

    projects(:orpheus).update!(buddy_skipped: false, buddy_invited: true)
    get project_path
    assert_select ".project__setup-done", count: 0 # a pending invite counts as done

    get project_path(step: "hackatime_project")
    assert_select ".project__setup-done", count: 0 # Change opens the tick list under Hours from, not the setup steps
    assert_select ".project__steps", count: 0
    assert_select ".project__linked .project__linked-panel:not([hidden]) .hkp", 1
    assert_select ".project__linked-change", /Done/
  end

    # Orpheus, set up and aiming for the 8BitDo Micro with `hours` logged, on the project page.
    def next_step_page(hours:, day: 2, pick: "micro")
      link_hackatime(users(:orpheus))
      during_program(hours, day:) do
        # The pace is set without its check: whether it finishes in time depends on today, and the real today is past the program's.
        projects(:orpheus).update!(prize_key: pick, hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
        projects(:orpheus).update_columns(pace_minutes: 45)
        sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
        get project_path
        assert_response :success
        yield
      end
    end

    # `hours` logged on the program's first day, and the block running `day` days after the start, at midday.
    def during_program(hours, day: 2, uid: "1001")
      before = Hackatime.stubbed_spans
      Hackatime.stubbed_spans = before.merge(uid => [ hackatime_span(Program::STARTS_AT + 3.hours, (hours * 60).round) ])
      travel_to(Program::STARTS_AT + day.days + 15.hours) { yield }
    ensure
      Hackatime.stubbed_spans = before
    end

    def ship_for_next_step(status)
      ship = projects(:orpheus).ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, and it is a game.",
                                              repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours: Prize.find("micro").hours,
                                              screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
      ship.update_columns(status == "approved" ? approved_columns(Prize.find("micro").hours) : { status: })
    end

  test "the pomodoro strip and the hours poll's stickers go quiet for an ineligible or Hackatime-banned account" do
    spans_before = Hackatime.stubbed_spans
    user = stickers_account
    travel_to Time.utc(2026, 10, 25, 10, 20) do
      get hours_project_path(refresh: 1)
      assert_equal "counting", response.parsed_body.dig("stickers", "kind")

      user.update_column(:hackatime_trust_level, "red")
      get project_path
      assert_select ".focus .focus-stickers", 0
      assert_select ".sticker-promise", 0
      get hours_project_path(refresh: 1)
      assert_nil response.parsed_body["stickers"]

      user.update_columns(hackatime_trust_level: "blue", ysws_eligible: false)
      get project_path
      assert_select ".focus .focus-stickers", 0
      get hours_project_path(refresh: 1)
      assert_nil response.parsed_body["stickers"]
    end
  ensure
    Hackatime.stubbed_spans = spans_before
  end
end
