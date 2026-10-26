require "test_helper"

class ProjectsHelperTest < ActionView::TestCase
  include ApplicationHelper

  include PagesHelper
  include ShopHelper
  include LandingHelper

  test "how to get hours onto Hackatime" do
    project = projects(:orpheus)

    assert_match(/Install Hackatime in the editor or engine you build your game in/, project_hackatime_how(project))
    project.hackatime_seen_seconds = 0
    assert_match(/seen any coding from you yet/, project_first_time_how(project))
    assert_includes project_first_time_how(project), %(href="#{hackatime_url}")
    project.hackatime_seen_seconds = 600
    assert_match(/Work on your game with Hackatime on/, project_first_time_how(project))
    assert_no_match(/Set it up in your editor/, project_first_time_how(project))
    assert_match(/Don't see it\? Work on your game with Hackatime on, then refresh/, project_hackatime_refresh_hint(project))
  end

  test "while there's nothing on Hackatime to pick, the project step and the bot say to log some time" do
    project = projects(:orpheus)
    link_hackatime(project.user)
    project.available_hackatime_projects = []

    step = project_steps(project).find { |item| item[:key] == "hackatime_project" }
    assert_equal [ "Log your first time on Hackatime", "it links itself" ], [ step[:title], step[:note] ]
    assert_equal "Hackatime's linked. Start building and your project links itself once you log time.", project_setup_note(project)
  end

  test "a repo put off till later has no done state, and a real repo URL does" do
    project = projects(:orpheus)
    link_hackatime(project.user)
    project.assign_attributes(hackatime_projects: [ "rhythm-game" ], repo_url: nil, repo_later: true, buddy_skipped: true)

    repo = project_steps(project, step: "buddy").find { |item| item[:key] == "repo" }
    assert_not repo[:done]
    assert repo[:later]
    assert_equal [ "Git repo", "add before you ship" ], [ repo[:title], repo[:note] ]
    buddy = project_steps(project, step: "repo").find { |item| item[:key] == "buddy" }
    assert_not buddy[:done]
    assert buddy[:later]

    project.repo_url = "https://github.com/orpheus/rhythm-game"
    repo = project_steps(project, step: "buddy").find { |item| item[:key] == "repo" }
    assert repo[:done]
    assert_not repo[:later]
    assert_equal "Repo added", repo[:title]
  end

  test "a prize tag's pace is what you still need for it, or Earned when your hours cover it" do
    project = projects(:orpheus)
    prize = Prize.find("aseprite")
    project.define_singleton_method(:hours_logged) { |**| 0 }
    assert_equal pace_html(prize.pace_minutes), project_prize_pace(project, prize)
    project.define_singleton_method(:hours_logged) { |**| prize.hours }
    assert_equal "Earned", project_prize_pace(project, prize)
  end

  test "the schedule fills in the days gone by how they went, then today, the goal day and the party" do
    with_hours_needed(10.0) { schedule_fills_in } # a pick that takes 10 hours
  end

  def schedule_fills_in
    project = projects(:orpheus)
    user = project.user
    user.streak_activities.create!(activity_date: Date.new(2026, 10, 23), coded_seconds: 45 * 60)
    user.streak_activities.create!(activity_date: Date.new(2026, 10, 24), coded_seconds: 20 * 60)
    user.streak_activities.create!(activity_date: Date.new(2026, 10, 26), coded_seconds: 90 * 60)

    days = project_schedule(project, today: Date.new(2026, 10, 27))
    assert_equal [ "hit", "some", "missed", "hit", "today", nil ], days.first(6).map { _1[:state] }
    assert_equal [ "45m", "20m", "0", "1.5h", "45m", "45m" ], days.first(6).map { _1[:value] }
    assert_equal [ "Oct 23", "24", "25", "26", "27", "28" ], days.first(6).map { _1[:date] }
    assert_equal({ date: "2", state: "due", value: "Due" }, days.last.slice(:date, :state, :value), "the goal, Nov 5, is past the deadline, so the deadline sits among your days")
    assert_equal 11, days.size, "Oct 23 to Nov 2"
    assert_nil days.find { _1[:state] == "goal" }

    user.streak_activities.create!(activity_date: Date.new(2026, 10, 27), coded_seconds: 50 * 60)
    today = project_schedule(project, today: Date.new(2026, 10, 27))[4]
    assert_equal({ date: "27", state: "today", value: "50m", built: "hit" }, today.slice(:date, :state, :value, :built), "today shows its time, and fills in")

    project.update!(pace_minutes: 20)
    days = project_schedule(project, today: Date.new(2026, 10, 27))
    assert_equal "due", days.find { _1[:date] == "2" }[:state], "the deadline sits among your days when they run past it"
    assert_equal "due", days.last[:state]

    project.update!(pace_minutes: 45)
    days = project_schedule(project, today: Date.new(2026, 10, 29))
    assert_equal [ "hit", "some", "missed", "hit", "hit", "missed", "today" ], days.first(7).map { _1[:state] }
    assert_equal "0", days[5][:value]
  end

  test "today's pace and the last day's tile never exceed what's left of your goal" do
    project = projects(:orpheus) # 45 min a day, evenings
    with_hours_needed(1.0) do
      assert_equal "Today: 45 min, this evening", project_today(project)
      days = project_schedule(project, today: Date.new(2026, 10, 23))
      assert_equal [ "45m", "15m" ], days.first(2).map { _1[:value] }, "the second session is only the 15 minutes left"
      assert_equal "goal", days[1][:state]
    end

    with_hours_needed(0.5) do
      assert_equal "Today: 30 min, this evening", project_today(project)
      assert_equal "30m", project_schedule(project, today: Date.new(2026, 10, 23)).first[:value]
    end

    with_hours_needed(0.0) do
      assert_equal "Today: 45 min, this evening", project_today(project), "nothing left to cap it"
    end
  end

  test "the schedule has a goal day, a gap and the deadline when your hours would be in well before it" do
    project = projects(:orpheus)
    project.update!(pace_minutes: 60)
    with_hours_needed(5.0) do # 5 sessions: Oct 23 to 27
      days = project_schedule(project, today: Date.new(2026, 10, 23))
      assert_equal [ "today", nil, nil, nil, "goal", nil, "due" ], days.map { _1[:state] }
      assert days[-2][:gap], "days skipped between the goal and the deadline"
      assert_equal({ date: "2", state: "due", value: "Due" }, days.last)
    end
  end

  test "the play party shows on its day, when it falls in your days" do
    project = projects(:orpheus)
    with_play_party_on(Date.new(2026, 10, 25)) do
      with_hours_needed(10.0) do
        assert_equal "party", project_schedule(project, today: Date.new(2026, 10, 23))[2][:state]
      end
    end
  end

  test "the schedule says when your hours would be in, and that you ship any time up to the deadline" do
    travel_to Time.utc(2026, 10, 23, 12) # the schedule counts from today, so it's pinned to day 1
    project = projects(:orpheus)
    assert_equal "9 sessions of 45 min gets you there by Oct 31. Ship any time up to Nov 2.", project_schedule_note(project)
    assert_equal({ label: "Logged", value: "0 of 6.5 hrs", note: "for the 8BitDo Micro" }, project_goal(project).first)
    assert_equal "6.5 hrs · 45 min a day · done by Oct 31 · 8BitDo Micro", project_meta(project)
  end

  test "a pace that isn't a preset is written as minutes" do
    assert_equal [ "45 min", "1 hr", "52 min", "1 hr 15 min" ], [ 45, 60, 52, 75 ].map { project_pace_label(_1) }
  end

  test "Done by reads Reached once your logged hours cover the prize" do
    project = projects(:orpheus)
    project.define_singleton_method(:hours_to_go) { 0 }
    assert_equal({ label: "Done by", value: "Reached", note: "you've logged enough" }, project_goal(project).last)
  end

  test "an approved extension doesn't move the deadline on the schedule" do
    travel_to Time.utc(2026, 10, 23, 12) # the schedule counts from today, so it's pinned to day 1
    project = projects(:orpheus)
    project.create_extension!(reason: "exams", status: "approved")
    assert_equal "9 sessions of 45 min gets you there by Oct 31. Ship any time up to Nov 2.", project_schedule_note(project)
    assert_equal({ date: "2", state: "due", value: "Due" }, project_schedule(project, today: Date.new(2026, 10, 29)).last.slice(:date, :state, :value))
  end

  test "the hours track runs to your pick, at the hours its price takes, with no mark on the way" do
    project = projects(:orpheus)
    assert_equal [ "6.5 hrs · 8BitDo Micro" ], project_milestones(project).map { _1[:label] }
    assert_equal [ true ], project_milestones(project).map { _1[:last] }
    assert_in_delta 100.0, project_milestones(project).first[:at], 0.1
    assert_equal 0, project_hours_percent(project)
  end

  test "the project dropdown lists recent projects, and keeps a linked one without recent time so it can be unlinked" do
    project = projects(:orpheus)
    link_hackatime(project.user)
    project.update_columns(hackatime_projects: [ "dotfiles" ])
    before = Hackatime.stubbed_recent_projects
    Hackatime.stubbed_recent_projects = { "1001" => [ "rhythm-game" ] }
    choices = project_hackatime_choices(project)[:projects]
    assert_equal [ "dotfiles", "rhythm-game" ], choices.map { |choice| choice[:name] }
    assert_equal [ true, false ], choices.map { |choice| choice[:linked] }
    assert_equal "3.1 hrs", choices.first[:note], "its time since the start, not a note that it's gone"
  ensure
    Hackatime.stubbed_recent_projects = before
  end

  # D-064: the picker lists a project Hackatime links to another repo last, with a warning, and it stays pickable.
  def picker_with_repos(links, repo_url: "https://github.com/orpheus/rhythm-game", linked: [])
    project = projects(:orpheus)
    link_hackatime(project.user)
    project.update_columns(repo_url:, hackatime_projects: linked)
    before = [ Hackatime.stubbed_recent_projects, Hackatime.stubbed_repo_urls ]
    Hackatime.stubbed_recent_projects = { "1001" => [ "dotfiles", "rhythm-game" ] }
    Hackatime.stubbed_repo_urls = { "1001" => links }
    yield project
  ensure
    Hackatime.stubbed_recent_projects, Hackatime.stubbed_repo_urls = before
  end

  test "the picker lists a project Hackatime links to another repo last, with a warning" do
    picker_with_repos({ "rhythm-game" => "https://github.com/orpheus/other-game" }) do |project|
      choices = project_hackatime_choices(project)[:projects]
      assert_equal [ "dotfiles", "rhythm-game" ], choices.map { |choice| choice[:name] }
      assert_equal [ false, true ], choices.map { |choice| choice[:other_repo] }
      assert_equal "1.5 hrs", choices.last[:note], "it keeps its hours"

      html = render partial: "shared/hackatime_rows", locals: { choices: }
      assert_equal 1, html.scan("Hackatime links this to a different repo").size
      assert_operator html.index("dotfiles"), :<, html.index("rhythm-game")
    end
  end

  test "a mismatched project that is already linked stays ticked, and last" do
    picker_with_repos({ "rhythm-game" => "https://github.com/orpheus/other-game" }, linked: [ "rhythm-game" ]) do |project|
      choices = project_hackatime_choices(project)[:projects]
      assert_equal [ "dotfiles", "rhythm-game" ], choices.map { |choice| choice[:name] }
      assert_equal [ false, true ], choices.map { |choice| choice[:linked] }
    end
  end

  test "a matching repo, no repo link on Hackatime, or no repo on the project gets no warning" do
    cases = [
      [ { "rhythm-game" => "http://www.GitHub.com/Orpheus/Rhythm-Game.git/" }, "https://github.com/orpheus/rhythm-game" ],
      [ {}, "https://github.com/orpheus/rhythm-game" ],
      [ { "rhythm-game" => "https://github.com/orpheus/other-game" }, nil ]
    ]
    cases.each do |links, repo_url|
      picker_with_repos(links, repo_url:) do |project|
        choices = project_hackatime_choices(project)[:projects]
        assert_equal [ "rhythm-game", "dotfiles" ], choices.map { |choice| choice[:name] }, "order unchanged"
        assert_equal [ false, false ], choices.map { |choice| choice[:other_repo] }
      end
    end
  end

  test "Hackatime is not asked for repo links when the project has no repo" do
    picker_with_repos(:unavailable, repo_url: nil) do |project|
      asked = Class.new(Hash) { def fetch(*) = raise("asked Hackatime for repo links") }.new
      Hackatime.stubbed_repo_urls = asked
      assert_equal [ false, false ], project_hackatime_choices(project)[:projects].map { |choice| choice[:other_repo] }
    end
  end

  test "the picker still lists every project, with no warnings, when repo links can't be read" do
    picker_with_repos(:unavailable) do |project|
      choices = project_hackatime_choices(project)
      assert_equal [ "rhythm-game", "dotfiles" ], choices[:projects].map { |choice| choice[:name] }
      assert_equal [ false, false ], choices[:projects].map { |choice| choice[:other_repo] }
      assert_nil choices[:problem]
      assert_no_match "different repo", render(partial: "shared/hackatime_rows", locals: { choices: choices[:projects] })
    end
  end

  def board(size, me:, off: false, admin: false)
    (1..size).map { |rank| { rank:, you: rank == me, off: off && rank == me, hidden: admin && rank == me } }
  end

  def window(rows, **) = leaderboard_window(rows, **).map { |row| row.is_a?(Array) ? row : row[:rank] }

  test "the board shows the top three, then you with five either side, and the gap between" do
    assert_equal [ 1, 2, 3, 4, 5, 6, 7, 8 ], window(board(30, me: 3)).first(8), "near the top the window touches the top three"
    assert_equal [ 1, 2, 3, [ :gap, 9 ], 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 ], window(board(30, me: 18)), "in the middle"
    assert_equal [ 1, 2, 3, [ :gap, 21 ], 25, 26, 27, 28, 29, 30 ], window(board(30, me: 30)), "at the bottom there are fewer below"
    assert_equal (1..10).to_a, window(board(10, me: 5)), "a short board is just the board"
  end

  test "someone with no time yet sees the top three and nothing ranked last" do
    assert_equal [ 1, 2, 3 ], window(board(31, me: 31, off: true))
    assert_equal [ 1, 2 ], window(board(3, me: 3, off: true))
  end

  test "the full list comes back when asked for, and admins always see it" do
    assert_equal (1..30).to_a, window(board(30, me: 18), all: true)
    assert_equal (1..29).to_a, window(board(30, me: 30, admin: true)), "an admin has no row, so no window"
  end
end
