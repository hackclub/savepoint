require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "signing in for the first time makes a user from Hack Club Auth's claims" do
    user = User.from_omniauth(mock_hack_club_auth)

    assert_equal "ident!heidi", user.hca_id
    assert_equal "heidi@hackclub.com", user.email
    assert_equal "Heidi Hakkuun", user.name
    assert_equal "Heidi", user.first_name
    assert_equal "U0HEIDI", user.slack_id
    assert_equal "verified", user.verification_status
    assert user.ysws_eligible
  end

  test "signing in again finds the same user and refreshes what changed" do
    user = users(:orpheus)
    assert_no_difference -> { User.count } do
      User.from_omniauth(mock_hack_club_auth(uid: user.hca_id, name: "Orpheus Hacksworth", ysws_eligible: false))
    end

    user.reload
    assert_equal "Orpheus Hacksworth", user.name
    assert_not user.ysws_eligible
  end

  test "everyone's picture colour is the same every time, and people mostly get different ones" do
    orpheus = users(:orpheus)
    assert_includes User::AVATAR_COLORS, orpheus.avatar_color
    assert_equal orpheus.avatar_color, User.find(orpheus.id).avatar_color

    colors = 200.times.map { |index| User.new(hca_id: "ident!#{index}").avatar_color }
    assert_operator colors.uniq.size, :>, 6, "the colours are spread out"
  end

  test "your timezone is remembered from your browser, if it's a real one" do
    user = users(:ana)
    user.remember_timezone("America/New_York")
    assert_equal "America/New_York", user.reload.timezone

    user.remember_timezone("Not/A_Zone")
    user.remember_timezone("")
    assert_equal "America/New_York", user.reload.timezone
  end

  test "a new timezone counts your streak days again" do
    user = users(:orpheus)
    link_hackatime(user)
    user.project.update!(hackatime_projects: [ "rhythm-game" ])

    assert_enqueued_with(job: StreakSyncJob, args: [ user.id ]) { user.remember_timezone("Asia/Kolkata") }
    assert_no_enqueued_jobs(only: StreakSyncJob) { user.remember_timezone("Asia/Kolkata") }
  end

  test "everyone else sees your Slack display name, then your Slack username, then a player number, never your real name" do
    user = users(:ana)
    assert_equal "pixelana", user.public_name

    user.update!(slack_display_name: nil, slack_username: "ana.l")
    assert_equal "ana.l", user.public_name

    user.update!(slack_username: nil)
    assert_match(/\APlayer [1-9]\d{0,3}\z|\APlayer 0\z/, user.public_name)
    assert_equal user.public_name, User.find(user.id).public_name, "the same every time"
    assert_no_match(/Ana|Lovelace|Anonymous/, user.public_name)
  end

  test "the name for a parcel is the preferred one, or else the Hack Club one, kept encrypted" do
    user = users(:ana)
    assert_equal "Ana Lovelace", user.recipient_name

    user.update!(preferred_name: "  Ada \n  Byron ")
    assert_equal "Ada Byron", user.reload.recipient_name
    assert_not_equal "Ada Byron", user.preferred_name_before_type_cast
    assert_not user.update(preferred_name: "x" * 121)

    user.update!(preferred_name: " ")
    assert_nil user.reload.preferred_name
    assert_equal "Ana Lovelace", user.recipient_name
  end

  test "an address is kept as Hack Club Auth shares it, encrypted, and needed till we have it" do
    assert_equal({ "street_address" => "15 Falls Rd", "locality" => "Shelburne", "country" => "US" },
                 User.address_from(street_address: " 15 Falls Rd ", locality: "Shelburne", region: "", country: "US", formatted: "x"))
    assert_equal HQ_ADDRESS, User.address_from(HQ_ADDRESS.to_json)
    assert_nil User.address_from(nil)
    assert_nil User.address_from("not json")

    user = users(:orpheus)
    assert_not user.needs_address?
    user.update!(address: nil)
    assert user.needs_address?

    user.update!(address: HQ_ADDRESS)
    assert_equal HQ_ADDRESS, user.reload.address
    assert_equal "15 Falls Rd\nShelburne, VT 05482\nUS", user.address_lines
    assert_no_match(/Falls/, User.connection.select_value("SELECT address FROM users WHERE id = #{user.id}"), "encrypted at rest")
    assert_not user.needs_address?
  end
end
