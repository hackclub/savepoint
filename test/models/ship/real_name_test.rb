require "test_helper"

# D-143: the app's reasons to doubt a name. It never says a name is real.
class Ship::RealNameTest < ActiveSupport::TestCase
  setup do
    @ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.",
                                         repo_url: "https://github.com/ana-l/pong", demo_url: "https://example.com/pong", hours: 3,
                                         screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    @user = @ship.project.user
  end

  def concern(first: "Ana", last: "Lovelace", **more)
    @user.update!(first_name: first, last_name: last, name: [ first, last ].join(" ").strip, **more)
    Ship::RealName.new(@ship.reload).concern
  end

  test "a plain first and last name raises no concern, and the default is still unticked" do
    assert_nil concern
    assert_nil concern(first: "Siobhan", last: "O'Brien-Smith")
    assert_nil concern(first: "Zoë", last: "Nguyễn")
    assert_nil concern(first: "Lynn", last: "Ng")
    unchecked = Ship::EarlierShip::Result.new(status: :not_configured, entry: nil, message: nil, entries: [])
    defaults = @ship.checklist_defaults(earlier: unchecked, limits: Ship::Limits.new(claimed: 3, ai_coding_seconds: 0, art_seconds: nil))
    assert_equal false, defaults["real_name"].first
    assert_match(/never ticks/, defaults["real_name"].last)
  end

  test "each doubt has a reason" do
    assert_match(/No HCA first name/, concern(first: "", last: "Smith"))
    assert_match(/No HCA last name/, concern(last: ""))
    assert_match(/one character/, concern(last: "L"))
    assert_match(/same word/, concern(first: "Madonna", last: "madonna"))
    assert_match(/digits or symbols/, concern(last: "Lovelace99"))
    assert_match(/digits or symbols/, concern(last: "Love_lace!"))
    assert_match(/keyboard mash/, concern(last: "Asdfgh"))
    assert_match(/keyboard mash/, concern(last: "Bcdfgk"))
    assert_match(/keyboard mash/, concern(last: "Aaaaa"))
  end

  test "a joke or placeholder name raises a concern, but a real surname like Mao does not" do
    assert_match(/joke or a placeholder/, concern(first: "Lol", last: "Mao"))
    assert_match(/joke or a placeholder/, concern(first: "Test", last: "User"))
    assert_match(/joke or a placeholder/, concern(first: "John", last: "Doe"))
    assert_match(/joke or a placeholder/, concern(first: "Ana", last: "Lmao"))
    assert_nil concern(first: "Wei", last: "Mao")
    assert_nil concern(first: "Johnny", last: "Doe")
  end

  test "a Real name tick keeps the names, who ticked and when, and stops counting when the names change" do
    reviewer = users(:orpheus)
    @ship.tick_checklist!("real_name", true, by: reviewer)
    @ship.reload
    assert_equal [ "Ana", "Lovelace" ], [ @ship.real_name_first, @ship.real_name_last ]
    assert_equal reviewer, @ship.real_name_ticked_by
    assert_not_nil @ship.real_name_ticked_at
    assert @ship.real_name_checked?
    assert_not @ship.real_name_stale?

    @user.update!(first_name: "Anya", last_name: "Lovelace", name: "Anya Lovelace")
    @ship.reload
    assert_not @ship.real_name_checked?, "the tick was for Ana"
    assert @ship.real_name_stale?
    assert_equal true, @ship.review_checklist["real_name"], "the tick stays as history"

    @ship.tick_checklist!("real_name", true, by: reviewer)
    assert @ship.reload.real_name_checked?
    @ship.tick_checklist!("real_name", false, by: reviewer)
    assert_nil @ship.reload.real_name_first
    assert_nil @ship.real_name_ticked_by
  end

  test "a name that is the Slack name or the GitHub username is a handle" do
    assert_match(/handle/, concern(first: "Pixel", last: "Ana", slack_display_name: "pixelana"))
    assert_match(/handle/, concern(last: "ana-l", slack_display_name: "x"))
    assert_match(/handle/, concern(last: "Lovelace", slack_username: "lovelace"))
  end

  test "the names are Hack Club Auth's given and family name, never the full name cut up" do
    @user.update!(name: "Ana the Great", first_name: "Ana", last_name: "Lovelace")
    assert_equal [ "Ana", "Lovelace" ], AirtableFields.names(@user)
    @user.update!(last_name: nil)
    assert_equal [ "Ana", nil ], AirtableFields.names(@user)
    assert_match(/No HCA last name yet, they need to sign in again/, Ship::RealName.new(@ship.reload).concern)
  end

  test "a ticked Real name does not pass for a user with no HCA last name" do
    @ship.tick_checklist!("real_name", true)
    assert @ship.real_name_checked?
    @user.update!(last_name: nil)
    assert_not @ship.reload.real_name_checked?
  end

  test "sign-in keeps the family name Hack Club Auth sends" do
    user = User.from_omniauth(mock_hack_club_auth)
    assert_equal "Hakkuun", user.last_name
    again = User.from_omniauth(mock_hack_club_auth(last_name: nil))
    assert_equal "Hakkuun", again.last_name, "kept when a sign-in does not share one"
  end
end
