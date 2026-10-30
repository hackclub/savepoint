require "test_helper"

# D-066: a game in the jame gam's Submission Form only counts time after its submission.
class JameGamTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @calls = []
    JameGam::Submissions.token = "pat-test"
    @user = users(:orpheus)
    @project = @user.project
    link_hackatime(@user)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
    clear_enqueued_jobs
  end

  teardown do
    JameGam::Submissions.token = nil
    Web.adapter = nil
  end

  def record(id, created, **fields) = { "id" => id, "createdTime" => created, "fields" => fields }

  # Answers each request with the next page, recording the url.
  def answer(*pages)
    Web.adapter = lambda do |_method, url, headers|
      @calls << [ url, headers ]
      Web::Response.new(status: 200, headers: {}, body: pages[[ @calls.size - 1, pages.size - 1 ].min].to_json)
    end
  end

  def submission(code_url: "", hackatime_names: "", at: Time.utc(2026, 10, 25, 10), status: "Pending")
    JameGam::Submissions::Submission.new(id: "recX", submitted_at: at, code_url:, hackatime_names:, review_status: status, jam: nil, game_title: nil)
  end

  def project_with(repo_url:, hackatime_projects:) = Project.new(repo_url:, hackatime_projects:)

  # The client.

  test "asks for only the listed fields, filtered by email or Slack ID, and reads the record's created time" do
    answer({ records: [ record("recA", "2026-10-25T10:00:00.000Z", code_url: "https://github.com/x/y", hackatime_names: "a, b", review_status: "Pending", jam: "Jame Gam 1", game_title: "Y") ] })
    result = JameGam::Submissions.for(@user)

    assert result.ok?
    entry = result.submissions.sole
    assert_equal [ "recA", Time.utc(2026, 10, 25, 10), "Pending" ], [ entry.id, entry.submitted_at, entry.review_status ]
    url, headers = @calls.sole
    assert_includes url, "/apprhNJsC9D4nlFRB/tblmnQSVJBu5EBoVY?"
    assert_equal "Bearer pat-test", headers["Authorization"]
    query = Rack::Utils.parse_nested_query(URI(url).query)
    assert_equal JameGam::Submissions::FIELDS, query["fields"]
    assert_equal %w[email slack_id code_url hackatime_names review_status jam game_title], query["fields"]
    assert_equal "OR(LOWER({email})='orpheus@hackclub.com', {slack_id}='U0ORPHEUS')", query["filterByFormula"]
  end

  test "escapes quotes in the formula" do
    answer({ records: [] })
    JameGam::Submissions.new(email: "o'brien@x.com", slack_id: "").fetch

    assert_includes Rack::Utils.parse_nested_query(URI(@calls.sole.first).query)["filterByFormula"], "o\\'brien@x.com"
  end

  test "follows the offset to the next page" do
    answer({ records: [ record("recA", "2026-10-25T10:00:00.000Z") ], offset: "itr1/recA" }, { records: [ record("recB", "2026-10-25T11:00:00.000Z") ] })
    result = JameGam::Submissions.for(@user)

    assert_equal %w[recA recB], result.submissions.map(&:id)
    assert_equal 2, @calls.size
    assert_equal "itr1/recA", Rack::Utils.parse_nested_query(URI(@calls.last.first).query)["offset"]
  end

  test "has nothing to say without a token, and never raises" do
    JameGam::Submissions.token = nil
    ENV.delete("JAMEGAM_AIRTABLE_TOKEN")
    Rails.application.credentials.stub(:dig, nil) { assert_equal :not_configured, JameGam::Submissions.for(@user).status }

    JameGam::Submissions.token = "pat-test"
    Web.adapter = ->(*) { raise Web::Error, "down" }
    assert_equal :error, JameGam::Submissions.for(@user).status
    Web.adapter = ->(*) { Web::Response.new(status: 403, headers: {}, body: "") }
    assert_match(/refused the token/, JameGam::Submissions.for(@user).message)
    Web.adapter = ->(*) { Web::Response.new(status: 200, headers: {}, body: "<html>") }
    assert_equal :error, JameGam::Submissions.for(@user).status
  end

  # The matcher: the real cases from 2026-10-26, anonymized.

  test "the same repo matches, however the URL is written" do
    assert submission(code_url: "https://github.com/SlayerArman/Dusty-Beetle").matches?(
      project_with(repo_url: "https://github.com/SlayerArman/Dusty-Beetle", hackatime_projects: [ "dusty" ]))
    assert submission(code_url: "https://github.com/SlayerArman/Dusty-Beetle.git").matches?(
      project_with(repo_url: "https://www.github.com/slayerarman/dusty-beetle/", hackatime_projects: []))
  end

  test "a shared Hackatime project name matches when the repo differs" do
    entry = submission(code_url: "https://github.com/someone-else/dontsteponme", hackatime_names: "don't-step-on-me")
    assert entry.matches?(project_with(repo_url: "https://github.com/someone-tech/Otto", hackatime_projects: [ "don't-step-on-me" ]))
  end

  test "any of several comma-separated names matches, ignoring case and spaces" do
    entry = submission(code_url: "https://github.com/a/other", hackatime_names: "lil guy with a gun, lil guy beats up big guys")
    project = project_with(repo_url: "https://github.com/a/wait-a-trillion-seconds", hackatime_projects: [ "Lil Guy Beats Up Big Guys", "lil guy with a gun" ])

    assert entry.matches?(project)
    assert submission(hackatime_names: "lil guy with a gun,lil guy beats up big guys").matches?(project_with(repo_url: "", hackatime_projects: [ " lil guy with a gun " ]))
  end

  test "a different game by the same person does not match" do
    entry = submission(code_url: "https://github.com/a/other-game", hackatime_names: "other-game")
    assert_not entry.matches?(project_with(repo_url: "https://github.com/a/this-game", hackatime_projects: [ "this-game" ]))
    assert_not submission.matches?(project_with(repo_url: "", hackatime_projects: [ "this-game" ])), "blank on both sides is not a match"
  end

  # hours_start.

  test "a submission after the launch and the sign-up moves the hours start, and says so" do
    @user.update_column(:created_at, Program::STARTS_AT + 1.day)
    @project.update_columns(jame_gam_submitted_at: Program::STARTS_AT + 2.days, jame_gam_review_status: "Pending")

    assert_equal Program::STARTS_AT + 2.days, @project.hours_start
    assert_equal :jame_gam, @project.hours_start_source
  end

  test "a submission before the sign-up changes nothing" do
    @user.update_column(:created_at, Program::STARTS_AT + 2.days)
    @project.update_columns(jame_gam_submitted_at: Program::STARTS_AT + 1.day)

    assert_equal Program::STARTS_AT + 2.days, @project.hours_start
    assert_equal :sign_up, @project.hours_start_source
  end

  test "a reviewer's override wins over a jame gam submission, even an earlier one" do
    @project.update_columns(jame_gam_submitted_at: Program::STARTS_AT + 2.days, hours_start_override: Program::STARTS_AT + 1.day)

    assert_equal Program::STARTS_AT + 1.day, @project.hours_start
    assert_equal :override, @project.hours_start_source
  end

  # The refresh.

  test "a matching submission is stored, with its status, and the days rebuild" do
    submitted = Time.utc(2026, 10, 25, 10)
    answer({ records: [ record("recA", "2026-10-25T10:00:00.000Z", hackatime_names: "rhythm-game", review_status: "Rejected"),
                        record("recOld", "2026-10-24T10:00:00.000Z", hackatime_names: "rhythm-game"),
                        record("recOther", "2026-10-25T20:00:00.000Z", code_url: "https://github.com/x/another", hackatime_names: "another") ] })
    @user.update_column(:streak_synced_at, Time.current)

    assert_enqueued_with(job: StreakSyncJob) { @project.refresh_jame_gam! }
    @project.reload
    assert_equal [ submitted, "recA", "Rejected" ], [ @project.jame_gam_submitted_at, @project.jame_gam_submission_id, @project.jame_gam_review_status ]
    assert_nil @user.reload.streak_synced_at

    clear_enqueued_jobs
    assert_no_enqueued_jobs { @project.refresh_jame_gam! }
  end

  test "a failed lookup leaves the stored submission alone" do
    @project.update_columns(jame_gam_submitted_at: Time.utc(2026, 10, 25, 10), jame_gam_submission_id: "recA")
    Web.adapter = ->(*) { Web::Response.new(status: 500, headers: {}, body: "") }

    assert_no_enqueued_jobs { assert_not @project.refresh_jame_gam!.ok? }
    assert_equal Time.utc(2026, 10, 25, 10), @project.reload.jame_gam_submitted_at

    JameGam::Submissions.token = nil
    ENV.delete("JAMEGAM_AIRTABLE_TOKEN")
    Rails.application.credentials.stub(:dig, nil) { @project.refresh_jame_gam! }
    assert_equal "recA", @project.reload.jame_gam_submission_id
  end

  test "a good answer with no match clears a stored submission" do
    @project.update_columns(jame_gam_submitted_at: Time.utc(2026, 10, 25, 10), jame_gam_submission_id: "recA")
    answer({ records: [] })

    assert_enqueued_with(job: StreakSyncJob) { @project.refresh_jame_gam! }
    assert_nil @project.reload.jame_gam_submitted_at
  end

  test "changing the Hackatime projects or the repo queues a look, and the job refreshes the project" do
    assert_enqueued_with(job: JameGamRefreshJob, args: [ @project.id ]) { @project.update!(repo_url: "https://github.com/orpheus/rhythm-game") }
    clear_enqueued_jobs
    assert_no_enqueued_jobs(only: JameGamRefreshJob) { @project.update!(idea: "A different idea") }

    answer({ records: [ record("recA", "2026-10-25T10:00:00.000Z", hackatime_names: "rhythm-game") ] })
    JameGamRefreshJob.perform_now(@project.id)
    assert_equal "recA", @project.reload.jame_gam_submission_id
    assert_nothing_raised { JameGamRefreshJob.perform_now(0) }
  end

  # D-121.

  test "every submission by the person is stored with nothing personal, and only this game's count" do
    answer({ records: [ record("recA", "2026-10-25T10:00:00.000Z", hackatime_names: "rhythm-game", review_status: "Rejected", jam: "Jam 3", game_title: "Rhythm",
                               email: "me@x.com", slack_id: "U1", code_url: "https://secret.example/x"),
                        record("recOld", "2026-10-24T10:00:00.000Z", hackatime_names: "rhythm-game", review_status: "Approved"),
                        record("recOther", "2026-10-26T20:00:00.000Z", code_url: "https://github.com/x/another", hackatime_names: "another", review_status: "Rejected") ] })
    @project.refresh_jame_gam!
    @project.reload

    assert_equal %w[recOther recA recOld], @project.jame_gam_submissions.map { it["id"] }, "newest first"
    assert_equal [ false, true, true ], @project.jame_gam_submissions.map { it["matches"] }
    assert_equal %w[id jam game_title review_status submitted_at matches].sort, @project.jame_gam_submissions.first.keys.sort
    assert_no_match(/me@x\.com|U1|secret|another"/, @project.jame_gam_submissions.to_json.sub('"another"', ""))
    assert_equal [ 2, 1 ], [ @project.jame_gam_match_count, @project.jame_gam_flagged_match_count ], "the other game's rejection does not count"
    assert_not_nil @project.jame_gam_checked_at
    assert_equal "recA", @project.jame_gam_submission_id
  end

  test "a failed lookup keeps the stored submissions and counts" do
    @project.update_columns(jame_gam_submissions: [ { "id" => "recA", "matches" => true, "review_status" => "Rejected" } ], jame_gam_match_count: 1,
                            jame_gam_flagged_match_count: 1, jame_gam_checked_at: Time.utc(2026, 10, 25))
    Web.adapter = ->(*) { Web::Response.new(status: 500, headers: {}, body: "") }
    @project.refresh_jame_gam!
    @project.reload
    assert_equal [ 1, 1, 1 ], [ @project.jame_gam_submissions.size, @project.jame_gam_match_count, @project.jame_gam_flagged_match_count ]
    assert_equal Time.utc(2026, 10, 25), @project.jame_gam_checked_at
  end

  test "any status but exactly Approved is flagged, a blank one too (D-122)" do
    [ "Rejected", "Pending", "Prize Only", "No Prize", "Needs Augie", "Stickers Only", nil, "", "  ", "Approved but late" ].each { assert JameGam.flagged?(it), it.inspect }
    [ "Approved", "approved", " Approved " ].each { assert_not JameGam.flagged?(it), it.inspect }
  end

  test "unapproved statuses list each distinct one of this game once, and the line reads from them (D-122)" do
    entry = ->(status, matches = true) { { "review_status" => status, "matches" => matches } }
    list = [ entry.("Rejected"), entry.("rejected "), entry.("Pending"), entry.("Approved"), entry.("No Prize", false), entry.(nil) ]
    assert_equal [ "Rejected", "Pending", "" ], JameGam.unapproved_statuses(list)
    assert_equal "This project was marked as Pending in jame gam", JameGam.status_line("Pending")
    assert_equal "This project hasn't been reviewed in jame gam yet", JameGam.status_line("")
  end

  test "the sweep queues every project, tracking or not, spread out, and does nothing without a token" do
    other = User.create!(hca_id: "ident!notrack", name: "No Track", first_name: "No", email: "notrack@hackclub.com")
    unlinked = Project.create!(user: other, idea: "idea", prize_key: "steam25", pace_minutes: 45, build_time: "evening", signed_on: "2026-09-30")
    assert_not unlinked.tracking?
    assert_enqueued_with(job: JameGamRefreshJob, args: [ @project.id ]) { JameGamSweepJob.perform_now }
    assert_enqueued_with(job: JameGamRefreshJob, args: [ unlinked.id ]) { JameGamSweepJob.perform_now }
    clear_enqueued_jobs

    JameGam::Submissions.token = nil
    ENV.delete("JAMEGAM_AIRTABLE_TOKEN")
    Rails.application.credentials.stub(:dig, nil) { assert_no_enqueued_jobs(only: JameGamRefreshJob) { JameGamSweepJob.perform_now } }
  end
end
