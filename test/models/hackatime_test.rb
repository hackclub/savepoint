require "test_helper"

class HackatimeTest < ActiveSupport::TestCase
  test "stats only count time since Hackatime time started counting" do
    assert_equal "/api/v1/users/my/stats?features=projects&start_date=2026-10-23", Hackatime.stats_path
  end

  test "the picker's stats start on the day D-013 names, apart from the hours' start" do
    assert_equal "/api/v1/users/my/stats?features=projects&start_date=2026-10-22", Hackatime.recent_stats_path
    assert_not_equal Program::HACKATIME_START, Program::HACKATIME_PICK_SINCE
  end

  test "pickable projects keep only those with recent time, and their time since the start" do
    user = users(:orpheus)
    link_hackatime(user)
    before = Hackatime.stubbed_recent_projects
    Hackatime.stubbed_recent_projects = { "1001" => [ "rhythm-game" ] }
    assert_equal [ Hackatime::Project.new("rhythm-game", 5400) ], Hackatime.pickable_projects(user)
    assert_equal 3, Hackatime.projects(user).size, "the full list still has everything, for hours and nudges"
  ensure
    Hackatime.stubbed_recent_projects = before
  end

  test "pickable projects need Hackatime linked" do
    assert_raises(Hackatime::NotLinked) { Hackatime.pickable_projects(users(:orpheus)) }
  end

  test "projects need Hackatime linked" do
    assert_raises(Hackatime::NotLinked) { Hackatime.projects(users(:orpheus)) }
  end
  test "spans ask for each project whole, so a comma in its name is not a list of projects" do
    path = Hackatime.spans_path([ "Game 26, Snake, GS", "WebOS 1" ], start_date: Date.new(2026, 10, 22), end_date: Date.new(2026, 11, 1))
    assert_equal "/api/v1/users/my/heartbeats/spans?end_date=2026-11-01&project%5B%5D=Game+26%2C+Snake%2C+GS&project%5B%5D=WebOS+1&start_date=2026-10-22", path
  end

  test "category time asks for the projects and one category, from a date to a time, with Hackatime's own total" do
    path = Hackatime.category_path([ "rhythm-game", "beat-art" ], "ai coding", from: Date.new(2026, 10, 23), to: Time.utc(2026, 10, 27, 15))
    assert_equal "/api/v1/users/my/stats?end_date=2026-10-27T15%3A00%3A00Z&filter_by_category=ai+coding&" \
                 "filter_by_project=rhythm-game%2Cbeat-art&start_date=2026-10-23&total_seconds=true", path
  end

  test "category time needs Hackatime linked, is none without projects, and unknown when a name has a comma" do
    user = users(:orpheus)
    window = { from: Program::HACKATIME_START, to: Time.current }
    assert_raises(Hackatime::NotLinked) { Hackatime.category_seconds(user, [ "rhythm-game" ], "ai coding", **window) }
    link_hackatime(user)
    assert_equal 0, Hackatime.category_seconds(user, [], "ai coding", **window)
    assert_nil Hackatime.category_seconds(user, [ "Game 26, Snake" ], "ai coding", **window), "filter_by_project would split it"
    Hackatime.stubbed_category_seconds = { "1001" => { "ai coding" => 1200 } }
    assert_equal 1200, Hackatime.category_seconds(user, [ "rhythm-game" ], "ai coding", **window)
    assert_equal 0, Hackatime.category_seconds(user, [ "rhythm-game" ], "designing", **window)
  ensure
    Hackatime.stubbed_category_seconds = {}
  end

  test "a stats answer's trust level is read and stored, only when it has one" do
    user = users(:orpheus)
    link_hackatime(user)
    trust = Hackatime.stubbed_trust_levels
    Hackatime.stubbed_trust_levels = nil

    with_hackatime_answer({ data: { projects: [] }, trust_factor: { trust_level: "red" } }.to_json) do
      assert_equal "red", Hackatime.refresh_trust_level!(user)
      assert user.reload.hackatime_banned?
    end
    with_hackatime_answer({ data: { projects: [] }, trust_factor: { trust_level: "green" } }.to_json) do
      assert_equal "green", Hackatime.refresh_trust_level!(user)
      assert_equal "green", user.reload.hackatime_trust_level
    end
    with_hackatime_answer({ data: { projects: [] } }.to_json) do
      assert_equal "green", Hackatime.refresh_trust_level!(user), "an answer without the field leaves what was stored"
    end
  ensure
    Hackatime.stubbed_trust_levels = trust
  end

  test "the projects and picker stats answers store the trust level too" do
    user = users(:orpheus)
    link_hackatime(user)
    before = [ Hackatime.stubbed_projects, Hackatime.stubbed_recent_projects ]
    Hackatime.stubbed_projects = nil
    Hackatime.stubbed_recent_projects = nil
    body = { data: { projects: [ { name: "rhythm-game", total_seconds: 60 } ] }, trust_factor: { trust_level: "yellow" } }.to_json
    with_hackatime_answer(body) do
      assert_equal [ Hackatime::Project.new("rhythm-game", 60) ], Hackatime.projects(user)
      assert_equal "yellow", user.reload.hackatime_trust_level

      user.update_column(:hackatime_trust_level, nil)
      Hackatime.pickable_projects(user)
      assert_equal "yellow", user.reload.hackatime_trust_level
    end
  ensure
    Hackatime.stubbed_projects, Hackatime.stubbed_recent_projects = before
  end

  test "an unlinked account has no trust level to refresh" do
    assert_raises(Hackatime::NotLinked) { Hackatime.refresh_trust_level!(users(:orpheus)) }
  end

  test "seconds per project count each name, never time before Save Point began (D-055, D-063)" do
    user = users(:orpheus)
    link_hackatime(user)
    before = Hackatime.stubbed_spans
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Program::STARTS_AT - 1.hour, 90), hackatime_span(Program::STARTS_AT + 1.hour, 30) ] }

    seconds = Hackatime.project_seconds(user, [ "rhythm-game", "dotfiles" ], (Program::STARTS_AT - 1.day)..(Program::STARTS_AT + 1.day))
    assert_equal({ "rhythm-game" => 1800 + 1800, "dotfiles" => 1800 + 1800 }, seconds, "half the first span is before the start")
    assert_equal({ "dotfiles" => 0 }, Hackatime.project_seconds(user, [ "dotfiles" ], (Program::STARTS_AT - 2.days)..(Program::STARTS_AT - 1.day)))
  ensure
    Hackatime.stubbed_spans = before
  end

  test "repo links are read from the projects/details answer, for the projects that have one" do
    user = users(:orpheus)
    link_hackatime(user)
    before = [ Hackatime.stubbed_projects, Hackatime.stubbed_repo_urls ]
    Hackatime.stubbed_projects = nil
    Hackatime.stubbed_repo_urls = nil
    body = { projects: [ { name: "rhythm-game", total_seconds: 60, repo_url: "https://github.com/orpheus/rhythm-game" },
                         { name: "dotfiles", total_seconds: 9, repo_url: nil }, { name: "scratch", total_seconds: 1, repo_url: "" } ] }.to_json
    with_hackatime_answer(body) do
      assert_equal({ "rhythm-game" => "https://github.com/orpheus/rhythm-game" }, Hackatime.repo_urls(user, refresh: true))
    end
    with_hackatime_answer("not json") do
      assert_raises(Hackatime::Unavailable) { Hackatime.repo_urls(user, refresh: true) }
    end
  ensure
    Hackatime.stubbed_projects, Hackatime.stubbed_repo_urls = before
  end

  test "repo links ask for every project since Hackatime started counting, as the signed-in user" do
    assert_equal "/api/v1/users/my/projects/details?start_date=2026-10-23", Hackatime.repo_urls_path
  end

  test "repo links need Hackatime linked" do
    assert_raises(Hackatime::NotLinked) { Hackatime.repo_urls(users(:orpheus)) }
  end
end
