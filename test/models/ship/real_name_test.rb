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
    @ship.update!(review_checklist: { "real_name" => true })
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
