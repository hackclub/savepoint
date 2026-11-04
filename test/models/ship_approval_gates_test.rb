require "test_helper"

# D-148: the gates on an approval live in Ship#decide!, so the review page and every other caller share them. A blocker no reason
# lifts (a repo Stardance reviews, a red Hackatime trust level) refuses. The others (Stardance unreadable, limits unknown, another
# program's overlap, a second account) refuse until the reviewer types a reason, which is kept with the ship.
class ShipApprovalGatesTest < ActiveSupport::TestCase
  setup do
    @project = projects(:orpheus)
    link_hackatime(@project.user)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
    @reviewer = users(:ana)
    travel_to(Program::STARTS_AT + 2.days)
    @project.user.streak_activities.create!(activity_date: (Program::STARTS_AT + 1.day).to_date, coded_seconds: 10 * 3600)
    @ship = ship_now
    @ship.update_columns(ai_coding_seconds: 0, art_seconds: 0, lapse_seconds: 0)
  end

  teardown { Web.adapter = nil }

  def approve(**more) = ticked(@ship).decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", **more)

  test "a repo Stardance reviews refuses an approval, and no reason lifts it (finding 4)" do
    Stardance.stubbed_status = :shipped
    assert_not approve(overrides: { "stardance" => "It is fine." })
    assert_includes @ship.errors[:base], "This repo is shipped on Stardance, so Stardance reviews it. Approve is off."
    assert @ship.reload.in_review?
    assert @ship.decide!("changes_needed", by: @reviewer, feedback: "Ship it on Stardance."), "the other verdicts stay open"
  end

  test "a Stardance that cannot be read refuses an approval until a reason is typed, and the reason is kept (finding 4)" do
    Stardance.stubbed_status = :unknown
    assert_not approve
    assert_includes @ship.errors[:base], "Stardance could not be checked. Type a reason to approve anyway."

    assert approve(overrides: { "stardance" => "  Checked its page by hand.  " })
    kept = @ship.reload.review_overrides["stardance"]
    assert_equal [ "Checked its page by hand.", @reviewer.id ], [ kept["reason"], kept["by"] ]
    assert kept["at"].present?
  end

  test "a red Hackatime trust level refuses an approval and a fraud pass, and blocks shipping (finding 6)" do
    Hackatime.stubbed_trust_levels = { @project.user.hackatime_uid => "red" }
    assert_not approve(overrides: { "trust" => "Please." })
    assert_includes @ship.errors[:base], "Hackatime's trust level for this person is red, so they can't be approved."
    assert_not @project.reload.may_ship?, "red trust can't ship"

    Hackatime.stubbed_trust_levels = { @project.user.hackatime_uid => "green" }
    @project.user.update_columns(hackatime_trust_level: "green")
    assert @project.reload.may_ship?
    assert approve
    @project.user.update_columns(hackatime_trust_level: "red")
    assert_not @ship.reload.pass_fraud!(by: @reviewer)
    assert_includes @ship.errors[:base], "Hackatime's trust level for this person is red, so they can't be approved."
  end

  test "the review page reads a fresh trust level, not the stored one (finding 6)" do
    @project.user.update_columns(hackatime_trust_level: "green")
    Hackatime.stubbed_trust_levels = { @project.user.hackatime_uid => "red" }
    assert_equal "red", Ship::Evidence.new(@ship).trust_level
  end

  test "limits Hackatime could not say refuse an approval until figures and a reason are typed (finding 8)" do
    @ship.update_columns(ai_coding_seconds: nil, art_seconds: nil, lapse_seconds: nil)
    assert_not approve
    assert_includes @ship.errors[:base], "Hackatime did not say how much was AI coding or art, so no cut applies. Type a reason to approve anyway."

    assert_not approve(overrides: { "limits" => "Looked fine to me." })
    assert_match(/Type the AI coding and art hours you checked/, @ship.errors[:base].to_sentence)

    assert approve(overrides: { "limits" => "AI coding 0 hrs and art 0 hrs, read by hand from Telescreen." })
    assert_match(/AI coding 0 hrs/, @ship.reload.review_overrides["limits"]["reason"])
  end

  # D-152: the Unified YSWS DB needs a full first and last name, so an approval needs both and Real name ticked. No reason lifts it.
  NAME_HEAD = "Approve needs a full first and last name with Real name ticked."

  test "a missing last name refuses an approval and the tick, and no reason lifts it (D-152)" do
    @project.user.update_columns(last_name: nil)
    message = "#{NAME_HEAD} Their last name is missing, so they need to sign in to Hack Club Auth again."
    assert_not @ship.tick_checklist!("real_name", true, by: @reviewer)
    assert_equal [ "Real name can't be ticked yet. Their last name is missing, so they need to sign in to Hack Club Auth again." ], @ship.errors[:base]
    assert_not @ship.reload.review_checklist.key?("real_name")

    assert_not @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", overrides: { "name" => "It is fine.", "real_name" => "Ticked by hand." })
    assert_equal [ message ], @ship.errors[:base]
    assert_equal [ message ], @ship.approval_blockers(frozen: {}).map(&:message)
    assert_not @ship.approval_blockers(frozen: {}).first.override
    assert @ship.reload.in_review?
  end

  test "an initial for the last name, with or without a dot, refuses like a missing one (D-152)" do
    [ "D", "D." ].each do |initial|
      @project.user.update_columns(last_name: initial)
      message = "#{NAME_HEAD} Their last name is an initial (#{initial}), so they need to enter their full name in Hack Club Auth and sign in again."
      assert_not @ship.tick_checklist!("real_name", true, by: @reviewer), initial
      assert_not approve(overrides: { "name" => "Their name is Salvador D." }), initial
      assert_equal [ message ], @ship.errors[:base], initial
      assert @ship.reload.in_review?
    end
  end

  test "a first name that is missing or an initial refuses too (D-152)" do
    @project.user.update_columns(first_name: "O")
    assert_not approve
    assert_equal [ "#{NAME_HEAD} Their first name is an initial (O), so they need to enter their full name in Hack Club Auth and sign in again." ], @ship.errors[:base]
    @project.user.update_columns(first_name: nil)
    assert_not approve
    assert_equal [ "#{NAME_HEAD} Their first name is missing, so they need to sign in to Hack Club Auth again." ], @ship.errors[:base]
  end

  test "a full name that is not ticked refuses an approval, and no reason lifts it (D-152)" do
    assert_not @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.", overrides: { "real_name" => "Looks real." })
    assert_equal [ "Tick Real name first." ], @ship.errors[:base]
    assert_not @ship.approval_blockers(frozen: {}).first.override
    assert @ship.reload.in_review?

    assert @ship.tick_checklist!("real_name", true, by: @reviewer)
    assert_empty @ship.approval_blockers(frozen: {}).select { %w[name real_name].include?(it.key) }
    assert @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
  end

  test "a tick made for another name no longer counts (D-152)" do
    @ship.tick_checklist!("real_name", true, by: @reviewer)
    @project.user.update_columns(last_name: "Other")
    assert_not @ship.decide!("approved", by: @reviewer, technical_features: "A rhythm grid.")
    assert_equal [ "Tick Real name first." ], @ship.errors[:base]
  end

  test "unticking Real name is always allowed, and the other verdicts do not need a name (D-152)" do
    @ship.tick_checklist!("real_name", true, by: @reviewer)
    @project.user.update_columns(last_name: nil)
    assert @ship.tick_checklist!("real_name", false, by: @reviewer)
    assert @ship.decide!("changes_needed", by: @reviewer, feedback: "Add a README.")
  end

  test "a ship already approved keeps its verdict when the name later has a problem (D-152)" do
    assert approve
    @project.user.update_columns(last_name: "D")
    assert @ship.reload.awaiting_fraud?
    assert @ship.pass_fraud!(by: users(:orpheus)), @ship.errors.full_messages.to_sentence
    assert @ship.reload.approved?
  end

  test "a linked Hackatime project name with a comma is refused at link time (finding 8)" do
    @project.hackatime_projects = [ "my,game" ]
    assert_not @project.valid?
    assert_match(/can't include a comma \(my,game\)/, @project.errors[:hackatime_projects].to_sentence)
  end

  test "moving the hours start clears the cached AI, art and Lapse seconds of ships in review (finding 9)" do
    @ship.update_columns(ai_coding_seconds: 3600, art_seconds: 1800, lapse_seconds: 600)
    @project.update!(hours_start_override: Program::STARTS_AT + 1.day)
    assert_equal [ nil, nil, nil ], [ @ship.reload.ai_coding_seconds, @ship.art_seconds, @ship.lapse_seconds ]
  end

  test "a reason for going below the rules has to name the cut or the hours approved (finding 10)" do
    assert_not approve(coding_hours: "5", deflation_reason: "A menu was cut.")
    assert_match(/Say how many hours you cut in the reason: 5 hrs, or the 5 hrs you approve/, @ship.errors[:deflation_reason].to_sentence)
    assert_not approve(coding_hours: "5", deflation_reason: ".")

    assert approve(coding_hours: "5", deflation_reason: "A menu was cut, 5 hours cut.")
    assert_equal "A menu was cut, 5 hours cut.", @ship.reload.deflation_reason
  end

  test "an overlap with another program refuses an approval until the reviewer ticks it away or types a reason (finding 11)" do
    defaults = { "not_double" => [ false, "The Unified YSWS DB has an earlier record of this person covering time after this project's hours began counting." ] }
    assert_not approve(checklist_defaults: defaults)
    assert_includes @ship.errors[:base], "The Unified YSWS DB has an earlier record of this person covering time after this project's hours began counting. Type a reason to approve anyway."

    assert approve(checklist_defaults: defaults, overrides: { "double" => "Their other record is a different build, 4 months apart." })
    assert @ship.reload.review_overrides["double"]["reason"].present?
  end

  test "a ticked not-double needs no reason (finding 11)" do
    defaults = { "not_double" => [ false, "x" ] }
    @ship.update!(review_checklist: { "not_double" => true })
    assert approve(checklist_defaults: defaults)
    assert_empty @ship.reload.review_overrides
  end

  test "the same Slack account on another account, or the same repo, refuses an approval until a reason is typed (finding 12)" do
    twin = User.create!(hca_id: "ident!twin", email: "twin@example.com", name: "Twin Orpheus", first_name: "Twin", slack_id: @project.user.slack_id)
    assert_not approve
    assert_includes @ship.errors[:base], "Another account has the same Slack account. Type a reason to approve anyway."
    assert approve(overrides: { "duplicate" => "Same teen, the old account is dead." })
    assert twin.persisted?
  end

  test "the same repo on another account refuses an approval too (finding 12)" do
    projects(:ana).update_columns(repo_url: @ship.repo_url)
    assert_not approve
    assert_includes @ship.errors[:base], "Another account has the same repository. Type a reason to approve anyway."
  end

  test "a ship with no gate in the way needs no override and keeps none" do
    assert approve
    assert_empty @ship.reload.review_overrides
  end

  test "a decided ship takes corrections to its words, not new links; a replaced ship takes nothing (finding 13)" do
    assert approve
    assert @ship.pass_fraud!(by: @reviewer)
    snapshot = Ship::Snapshot.new(@ship.reload)
    assert_equal true, snapshot.update({ title: "Beat Sheet, fixed" }, by: @reviewer)
    assert_equal "Beat Sheet, fixed", @ship.reload.title
    assert_equal 1, AdminAuditEvent.where(tool: "edit_ship").count, "the correction is logged"

    snapshot = Ship::Snapshot.new(@ship.reload)
    assert_equal false, snapshot.update({ repo_url: "https://github.com/someone/else" }, by: @reviewer)
    assert_match(/Only a ship in review takes new links/, snapshot.errors[:base].to_sentence)
    assert_equal "https://github.com/orpheus/beat-sheet", @ship.reload.repo_url

    @ship.update_columns(status: "superseded")
    snapshot = Ship::Snapshot.new(@ship.reload)
    assert_equal false, snapshot.update({ title: "Another" }, by: @reviewer)
    assert_equal Ship::REPLACED_MESSAGE, snapshot.errors[:base].first
  end

  test "a repo with no commit, an empty repo, or a commit read that failed is said in red; commits clear it (D-146)" do
    evidence = -> { Ship::Evidence.new(@ship) }
    Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 200, headers: {}, body: "[]") }
    assert_match(/no commits since this project's hours began counting/, evidence.().no_code_in_git)

    Web.adapter = ->(_method, _url, _headers) { Web::Response.new(status: 500, headers: {}, body: "") }
    assert_match(/The commits could not be read/, evidence.().no_code_in_git)

    Web.adapter = lambda do |_method, url, _headers|
      next Web::Response.new(status: 409, headers: {}, body: "{}") if url.include?("/commits")

      Web::Response.new(status: 200, headers: {}, body: { full_name: "orpheus/beat-sheet", pushed_at: nil, stargazers_count: 0 }.to_json)
    end
    assert_match(/The repository is empty/, evidence.().no_code_in_git)

    Web.adapter = lambda do |_method, url, _headers|
      body = url.include?("/commits") ? [ { sha: "abcdef123", commit: { message: "first", author: { name: "O", date: Time.current.iso8601 } }, html_url: "x" } ].to_json : "{}"
      Web::Response.new(status: 200, headers: {}, body:)
    end
    assert_nil evidence.().no_code_in_git
  end

  private
    def ship_now
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             changes_made: "Added a combo meter.", repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours: 10, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end
end
