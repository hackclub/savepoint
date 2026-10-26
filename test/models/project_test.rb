require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "its title is its name, or its idea" do
    assert_equal "a rhythm game", projects(:orpheus).title
  end

  test "build days run from the day Save Point starts, one session of the pace a day, until the hours are in" do
    travel_to Time.utc(2026, 10, 23, 12) # the schedule counts from today, so it's pinned to day 1
    project = projects(:orpheus) # 45 min a day, signed before Save Point starts

    with_hours_needed(10.0) do # a pick that takes 10 hours
      assert_equal 14, project.build_days.size
      assert_equal Date.new(2026, 10, 23), project.build_days.first
      assert_equal Date.new(2026, 11, 5), project.finish_on
    end
  end

  test "signing after Save Point starts counts from that day" do
    project = projects(:orpheus)
    project.user.created_at = Time.utc(2026, 10, 25, 12) # hours_start is the sign-up (D-065)

    assert_equal Date.new(2026, 10, 25), project.build_start
    assert_equal Date.new(2026, 10, 25), project.build_days.first
  end

  test "a jame gam submission moves the first build day to its day (D-065, D-066)" do
    travel_to Time.utc(2026, 10, 28, 12)
    project = projects(:orpheus) # signed before Save Point starts
    project.jame_gam_submitted_at = Time.utc(2026, 10, 25, 9)

    with_hours_needed(10.0) do
      assert_equal Date.new(2026, 10, 25), project.build_start
      assert_equal Date.new(2026, 10, 25), project.build_days.first, "nothing before Oct 25"
      assert_equal (Date.new(2026, 10, 28)..Program::DATES.end).count, project.days_left
    end
  end

  test "a start is a day in your timezone, like a streak day" do
    project = projects(:orpheus)
    project.user.timezone = "Australia/Sydney"
    project.jame_gam_submitted_at = Time.utc(2026, 10, 25, 20) # 7am on the 26th in Sydney

    assert_equal Date.new(2026, 10, 26), project.build_start
  end

  test "a reviewer's earlier start brings the first build day back to Save Point's (D-065)" do
    project = projects(:orpheus)
    project.user.created_at = Time.utc(2026, 10, 25, 12)
    project.hours_start_override = Program::STARTS_AT + 1.hour

    assert_equal Program::DATES.begin, project.build_start
    assert_equal Program::DATES.begin, project.build_days(today: Date.new(2026, 10, 26)).first, "the days gone count from there"
  end

  test "building on weekends only counts Saturdays and Sundays" do
    travel_to Time.utc(2026, 10, 23, 12) # the schedule counts from today, so it's pinned to day 1
    project = projects(:orpheus)
    project.assign_attributes(build_time: "weekends", pace_minutes: 180)

    with_hours_needed(10.0) do
      assert_equal [ Date.new(2026, 10, 24), Date.new(2026, 10, 25), Date.new(2026, 10, 31), Date.new(2026, 11, 1) ], project.build_days
    end
  end

  test "setting up takes linking Hackatime; your project, a repo and a buddy can wait" do
    project = projects(:orpheus)
    assert_equal 0, project.required_steps_done
    assert project.step_locked?("hackatime_project")

    link_hackatime(project.user)
    project.hackatime_projects = [ "rhythm-game" ]
    assert project.tracking?
    assert_not project.step_locked?("hackatime_project")
    assert project.set_up?, "linking Hackatime is all setup needs"
    assert_equal 2, project.optional_steps_left

    project.assign_attributes(repo_later: true, buddy_skipped: true)
    assert_equal 0, project.optional_steps_left
    assert project.step_open?("repo"), "a repo put off till later can still be added"
    assert_not project.step_open?("slack"), "Slack isn't a setup step"
  end

  test "renaming it changes its title, and renaming it to nothing puts back your idea" do
    project = projects(:orpheus)
    project.update!(name: "  Beat Sheet  ")
    assert_equal "Beat Sheet", project.title

    project.update!(name: " ")
    assert_nil project.name
    assert_equal "a rhythm game", project.title
  end

  test "asking Hackatime for projects keeps what it showed, and a failed ask keeps the last look" do
    project = projects(:orpheus)
    assert_nil project.hackatime_seen_at

    freeze_time do
      project.available_hackatime_projects = [ Hackatime::Project.new("a", 600), Hackatime::Project.new("b", 900) ]
      project.reload
      assert_equal [ 2, 1500, Time.current ], project.attributes.values_at("hackatime_seen_count", "hackatime_seen_seconds", "hackatime_seen_at")
    end

    project.available_hackatime_projects = nil
    assert_nil project.available_hackatime_projects
    assert_equal [ 2, 1500 ], project.reload.attributes.values_at("hackatime_seen_count", "hackatime_seen_seconds")

    project.available_hackatime_projects = []
    assert_equal [ 0, 0 ], project.reload.attributes.values_at("hackatime_seen_count", "hackatime_seen_seconds"), "no projects is something Hackatime said"
  end

  test "a project that isn't saved yet writes nothing when Hackatime is asked" do
    project = users(:orpheus).build_project
    project.available_hackatime_projects = [ Hackatime::Project.new("a", 600) ]
    assert_equal 1, project.available_hackatime_projects.size
    assert_nil project.hackatime_seen_count
  end

  test "a screenshot has to be an image, and not a huge one" do
    project = projects(:orpheus)
    project.screenshot.attach(io: file_fixture("notes.txt").open, filename: "notes.txt", content_type: "text/plain")
    assert_not project.valid?
    assert_equal [ "Screenshot should be a still PNG, JPEG or WebP, not a GIF" ], project.errors.full_messages

    project.screenshot.attach(io: file_fixture("screenshot.png").open, filename: "screenshot.png", content_type: "image/png")
    assert project.valid?
  end

  test "the ticked Hackatime projects are the linked ones, and new ones have to be on Hackatime" do
    project = projects(:orpheus)
    link_hackatime(project.user)
    project.available_hackatime_projects = Hackatime.projects(project.user)
    project.hackatime_project_names = [ "rhythm-game", "", "dotfiles", "rhythm-game" ]
    assert project.valid?
    assert_equal [ "rhythm-game", "dotfiles" ], project.hackatime_projects
    project.save!

    project.hackatime_project_names = [ "dotfiles", "not-mine" ]
    assert_not project.valid?
    assert_equal [ "Hackatime projects don't include not-mine on Hackatime" ], project.errors.full_messages

    project.available_hackatime_projects = []
    project.hackatime_project_names = [ "dotfiles" ]
    assert project.valid?, "ones already linked stay linkable, even once Hackatime stops listing them"

    project.hackatime_project_names = []
    assert_not project.valid?

    link_hackatime(project.user)
    project.hackatime_projects = [ "rhythm-game" ]
    assert project.step_done?("hackatime_project")
    assert project.step_open?("hackatime_project")
  end

  test "only takes the answers onboarding offers" do
    project = projects(:orpheus)
    project.assign_attributes(pace_minutes: 7, build_time: "never",
                              repo_url: "my repo")

    assert_not project.valid?
    assert_equal %i[pace_minutes build_time repo_url].sort, project.errors.attribute_names.sort
  end
end

class ProjectPrizeTest < ActiveSupport::TestCase
  setup { @project = projects(:orpheus) }

  test "a prize from Prize::ALL sets the hours, the name and the pace" do
    @project.update!(prize_key: "u2c")
    assert_equal Prize.find("u2c"), @project.chosen_prize
    assert_equal [ Prize.find("u2c").hours, "8BitDo Ultimate 2C", "8BitDo Ultimate 2C" ], [ @project.hours_needed, @project.prize_name, @project.prize_short ]
    assert_equal "8BitDo Ultimate 2C", @project.prize_configuration
  end

  test "the prize comes from the list, and a project needs one" do
    @project.prize_key = "nope"
    assert_not @project.valid?
    assert_equal [ :prize_key ], @project.errors.attribute_names

    @project.assign_attributes(prize_key: nil)
    assert_not @project.valid?
    assert_equal [ :prize_key ], @project.errors.attribute_names

    @project.assign_attributes(prize_key: "aseprite")
    assert @project.valid?
  end

  test "a new project's pace is the smallest one that covers its prize's daily pace" do
    prize = Prize.find("aseprite")
    assert_includes Project::PACES, Project.pace_for(prize)
    assert_operator Project.pace_for(prize), :>=, [ prize.pace_minutes, Project::PACES.last ].min
  end

  test "a game is titled by its name" do
    game = Project.new(idea: "Pixel Pirates")
    assert_equal "Pixel Pirates", game.title
    game.name = "Pixel Pirates 2"
    assert_equal "Pixel Pirates 2", game.title
  end
end

class ProjectDeadlineTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "Save Point runs 10 days, from Oct 23 21:00 UTC to Nov 2 21:00 UTC (D-017)" do
    assert_equal Time.utc(2026, 10, 23, 21), Program::STARTS_AT
    assert_equal Time.utc(2026, 11, 2, 21), Program::ENDS_AT
    assert_equal Date.new(2026, 10, 23)..Date.new(2026, 11, 2), Program::DATES
    assert_equal Date.new(2026, 10, 23), Program::HACKATIME_START
    assert_equal Date.new(2026, 10, 23), Program::FIRST_STREAK_DATE, "21:00 UTC is 07:00 the next morning at UTC-12 and then 2am has passed"
    assert_equal 10, Program.day(Program::ENDS_AT - 1)[:total]
  end

  test "the deadline is Save Point's last day, extension or not" do
    project = projects(:orpheus)
    assert_equal Program::ENDS_AT.to_date, project.deadline

    extension = project.create_extension!(reason: "exams")
    assert_equal Date.new(2026, 11, 2), project.reload.deadline
    extension.update!(status: "approved")
    assert_equal Date.new(2026, 11, 2), project.reload.deadline
    assert_equal Date.new(2026, 10, 23)..Date.new(2026, 11, 2), project.program_dates
  end

  test "ship closes at the end of the deadline where you are, plus two quiet days" do
    project = projects(:orpheus)
    assert_equal Time.utc(2026, 11, 4, 23, 59, 59), project.ship_cutoff.change(usec: 0), "UTC until they've said where they are"

    users(:orpheus).update!(timezone: "America/New_York")
    assert project.reload.may_ship?(now: Time.utc(2026, 11, 5, 3))
    assert_not project.may_ship?(now: Time.utc(2026, 11, 5, 6))
  end

  test "nobody can ask for more time any more" do
    project = projects(:orpheus)
    link_hackatime(users(:orpheus))
    project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    assert_not project.reload.extension_requestable?(now: Time.utc(2026, 10, 29, 12)), "set up, unshipped, and early"
  end
  test "the repo link is http or https only" do
    project = projects(:orpheus)
    [ "javascript:alert(1)", "JAVASCRIPT:alert(1)", "data:text/html,x", "https://", "ftp://example.com/x", "https://exa mple.com" ].each do |url|
      project.repo_url = url
      assert_not project.valid?, "#{url} should not pass"
      assert project.errors.added?(:repo_url, :invalid, value: url) || project.errors[:repo_url].any?
    end
    [ "https://github.com/orpheus/beat-sheet", "http://example.com:8080/a?b=1#c" ].each do |url|
      project.repo_url = url
      assert project.valid?, "#{url} should pass: #{project.errors.full_messages.to_sentence}"
    end
  end

  test "a repo link without a scheme gets https://, and junk is turned down" do
    project = projects(:orpheus)
    { "github.com/x/y" => "https://github.com/x/y", " github.com/x/y " => "https://github.com/x/y",
      "https://github.com/x/y" => "https://github.com/x/y" }.each do |typed, saved|
      project.repo_url = typed
      assert project.valid?, "#{typed} should pass: #{project.errors.full_messages.to_sentence}"
      assert_equal saved, project.repo_url
    end
    [ "junk", "hello world", "github", "///" ].each do |typed|
      project.repo_url = typed
      assert_not project.valid?, "#{typed} should not pass"
      assert project.errors[:repo_url].any?
    end
  end

  def hackatime_project(name, seconds) = Hackatime::Project.new(name, seconds)

  def auto_linkable_project
    link_hackatime(users(:orpheus))
    projects(:orpheus).tap { |project| project.update_columns(hackatime_projects: [], hackatime_baseline: nil, hackatime_baseline_seconds: nil) }
  end

  test "noting the baseline keeps each project's seconds too, and links nothing" do
    project = auto_linkable_project

    assert_nil project.auto_link_hackatime_project([ hackatime_project("old-game", 600), hackatime_project("dotfiles", 90) ])
    project.reload
    assert_equal %w[old-game dotfiles], project.hackatime_baseline
    assert_equal({ "old-game" => 600, "dotfiles" => 90 }, project.hackatime_baseline_seconds)
    assert_empty project.hackatime_projects
  end

  test "a continued game links itself once its project gains time after the baseline" do
    project = auto_linkable_project
    project.auto_link_hackatime_project([ hackatime_project("old-game", 600), hackatime_project("dotfiles", 90) ])

    assert_nil project.auto_link_hackatime_project([ hackatime_project("old-game", 600), hackatime_project("dotfiles", 90) ]), "unchanged time doesn't link"
    assert_empty project.reload.hackatime_projects

    assert_equal "old-game", project.auto_link_hackatime_project([ hackatime_project("old-game", 900), hackatime_project("dotfiles", 90) ])
    project.reload
    assert_equal [ "old-game" ], project.hackatime_projects
    assert project.hackatime_auto_linked?
  end

  test "the project that gained the most links, whether new or continued" do
    project = auto_linkable_project
    project.auto_link_hackatime_project([ hackatime_project("old-game", 600) ])

    assert_equal "new-game", project.auto_link_hackatime_project([ hackatime_project("old-game", 700), hackatime_project("new-game", 400) ])
  end

  test "a continued game that gained more than a new project wins" do
    project = auto_linkable_project
    project.auto_link_hackatime_project([ hackatime_project("old-game", 600) ])

    assert_equal "old-game", project.auto_link_hackatime_project([ hackatime_project("old-game", 1_000), hackatime_project("new-game", 120) ])
  end

  test "the auto-link DM escapes the title and the Hackatime project name" do
    project = auto_linkable_project
    project.update_columns(name: "<!channel> Beat")
    project.auto_link_hackatime_project([ hackatime_project("<https://evil.example|old-game>", 600) ])

    assert_equal "<https://evil.example|old-game>", project.auto_link_hackatime_project([ hackatime_project("<https://evil.example|old-game>", 900) ])
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_includes dm[:args].second, "*&lt;https://evil.example|old-game&gt;*"
    assert_includes dm[:args].second, "*&lt;!channel&gt; Beat*"
    assert_no_match(/<!channel>|<https/, dm[:args].second)
  end

  test "a baseline noted before seconds were kept counts every project's time as new" do
    project = auto_linkable_project
    project.update_columns(hackatime_baseline: %w[old-game dotfiles])

    assert_equal "dotfiles", project.auto_link_hackatime_project([ hackatime_project("old-game", 600), hackatime_project("dotfiles", 900) ])
  end

  # D-064: with both repos known and different, the Hackatime project is another game.
  def with_hackatime_repos(links)
    before = Hackatime.stubbed_repo_urls
    Hackatime.stubbed_repo_urls = { "1001" => links }
    yield
  ensure
    Hackatime.stubbed_repo_urls = before
  end

  def auto_linkable_project_with_repo(repo_url = "https://github.com/orpheus/rhythm-game")
    auto_linkable_project.tap do |project|
      project.update_columns(repo_url:)
      project.auto_link_hackatime_project([ hackatime_project("rhythm-game", 0), hackatime_project("dotfiles", 0) ])
    end
  end

  test "a Hackatime project linked to a different repo is skipped, and the next best links" do
    project = auto_linkable_project_with_repo
    with_hackatime_repos("dotfiles" => "https://github.com/orpheus/dotfiles") do
      assert_equal "rhythm-game", project.auto_link_hackatime_project([ hackatime_project("rhythm-game", 100), hackatime_project("dotfiles", 5000) ])
    end
  end

  test "a mismatched repo with nothing else to link links nothing" do
    project = auto_linkable_project_with_repo
    with_hackatime_repos("dotfiles" => "https://github.com/orpheus/dotfiles") do
      assert_nil project.auto_link_hackatime_project([ hackatime_project("rhythm-game", 0), hackatime_project("dotfiles", 5000) ])
    end
    assert_empty project.reload.hackatime_projects
  end

  test "a Hackatime project linked to the same repo links, however the link is written" do
    project = auto_linkable_project_with_repo
    with_hackatime_repos("dotfiles" => "http://www.GitHub.com/Orpheus/Rhythm-Game.git/") do
      assert_equal "dotfiles", project.auto_link_hackatime_project([ hackatime_project("rhythm-game", 100), hackatime_project("dotfiles", 5000) ])
    end
  end

  test "a Hackatime project with no repo link links as before" do
    project = auto_linkable_project_with_repo
    with_hackatime_repos("rhythm-game" => "https://github.com/orpheus/rhythm-game") do
      assert_equal "dotfiles", project.auto_link_hackatime_project([ hackatime_project("rhythm-game", 100), hackatime_project("dotfiles", 5000) ])
    end
  end

  test "a project with no repo links as before, and Hackatime isn't asked for repo links" do
    project = auto_linkable_project_with_repo(nil)
    asked = false
    original = Hackatime.method(:repo_urls)
    Hackatime.define_singleton_method(:repo_urls) { |*, **| asked = true; {} }
    assert_equal "dotfiles", project.auto_link_hackatime_project([ hackatime_project("rhythm-game", 100), hackatime_project("dotfiles", 5000) ])
    assert_not asked
  ensure
    Hackatime.define_singleton_method(:repo_urls, original)
  end

  test "when Hackatime can't answer for repo links, the project links as before" do
    project = auto_linkable_project_with_repo
    with_hackatime_repos(:unavailable) do
      assert_equal "dotfiles", project.auto_link_hackatime_project([ hackatime_project("rhythm-game", 100), hackatime_project("dotfiles", 5000) ])
    end
  end

  test "an expired Hackatime link for repo links doesn't stop auto-link either" do
    project = auto_linkable_project_with_repo
    original = Hackatime.method(:repo_urls)
    Hackatime.define_singleton_method(:repo_urls) { |*, **| raise Hackatime::Expired }
    assert_equal "dotfiles", project.auto_link_hackatime_project([ hackatime_project("rhythm-game", 100), hackatime_project("dotfiles", 5000) ])
  ensure
    Hackatime.define_singleton_method(:repo_urls, original)
  end
end
