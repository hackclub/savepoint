require "test_helper"

class StuckPeopleTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 27, 12)

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    travel_to NOW
    @signed_in = person("signed_in")
    @no_pledge = person("no_pledge", linked: true)
    @not_picked = users(:ana)
    @no_time = person("no_time", project: true, picked: true)
    @quiet = person("quiet", project: true, picked: true, coded: Date.new(2026, 10, 25))
    @building = person("building", project: true, picked: true, coded: Date.new(2026, 10, 26))
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "each person who stopped is in the group of the furthest step they reached, and nobody still building is in one" do
    groups = StuckPeople.new(now: NOW).groups.to_h { [ it.key, it.people.map(&:user) ] }

    assert_equal [ @quiet ], groups[:quiet]
    assert_equal [ @no_time ], groups[:no_time]
    assert_equal [ @not_picked ], groups[:not_picked]
    assert_equal [ @no_pledge ], groups[:no_pledge]
    assert_equal [ @signed_in ], groups[:signed_in]
    assert_not groups.values.flatten.include?(@building)
  end

  test "the groups come most actionable first, with counts" do
    groups = StuckPeople.new(now: NOW).groups
    assert_equal %i[quiet no_time not_picked no_pledge signed_in], groups.map(&:key)
    assert_equal [ 1, 1, 1, 1, 1 ], groups.map(&:total)
  end

  test "admins, banned accounts and people who have shipped are left out" do
    banned = person("banned")
    banned.update_columns(banned_at: NOW)
    shipper = person("shipper", project: true, picked: true, coded: Date.new(2026, 10, 24))
    Ship.insert_all!([ { project_id: shipper.project.id, title: "Game", description: "A game.", repo_url: "https://github.com/x/y", demo_url: "https://x.y", hours: 1, created_at: NOW, updated_at: NOW } ])
    users = StuckPeople.new(now: NOW).groups.flat_map { |group| group.people.map(&:user) }

    assert_not_includes users, users(:orpheus)
    assert_not_includes users, banned
    assert_not_includes users, shipper.reload
  end

  test "a person row carries sign-up, last seen and last page, and each list is longest-seen-last and capped" do
    @signed_in.update_columns(last_seen_at: NOW - 3.hours, last_seen_path: "/onboarding")
    row = StuckPeople.new(now: NOW).groups.find { it.key == :signed_in }.people.first

    assert_equal @signed_in.created_at, row.signed_up_at
    assert_equal NOW - 3.hours, row.last_seen_at
    assert_equal "/onboarding", row.last_path
    assert_equal 50, StuckPeople::LIMIT
  end

  private
    def person(name, linked: false, project: false, picked: false, coded: nil)
      user = User.create!(hca_id: "ident!#{name}", first_name: name, slack_display_name: name, created_at: NOW - 2.days)
      user.update_columns(hackatime_uid: "1#{user.id}", hackatime_access_token: "t") if linked
      if project
        made = Project.create!(user:, idea: "x", prize_key: "u2c", pace_minutes: 20, build_time: "evening", signed_on: Date.new(2026, 10, 24))
        made.update_columns(hackatime_projects: [ "game" ]) if picked
      end
      user.streak_activities.create!(activity_date: coded, coded_seconds: 600) if coded
      user
    end
end
