require "test_helper"

# D-063: who is working on a ship, so two admins don't review the same one.
class ClaimTest < ActiveSupport::TestCase
  setup do
    @ship = projects(:orpheus).ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                                             repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat", hours: 3,
                                             screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    @ana, @orpheus = users(:ana), users(:orpheus)
  end

  test "the first admin takes the claim, and another can't while it is live" do
    claim, took = Claim.acquire(@ship, "review", @ana)
    assert took
    assert_equal @ana, claim.user
    assert Claim.held_by_other?(@ship, "review", @orpheus)
    assert_not Claim.held_by_other?(@ship, "review", @ana)
    assert_not Claim.held_by_other?(@ship, "fraud", @orpheus), "a claim is per stage"

    claim, took = Claim.acquire(@ship, "review", @orpheus)
    assert_not took
    assert_equal @ana, claim.reload.user
  end

  test "the holder's beat keeps it, and a stale claim is anyone's" do
    Claim.acquire(@ship, "review", @ana)
    travel_to(80.seconds.from_now) { assert Claim.acquire(@ship, "review", @ana).last, "a beat from the holder" }
    travel_to(150.seconds.from_now) { assert Claim.held_by_other?(@ship, "review", @orpheus), "the beat at 80 s kept it live" }
    travel_to(200.seconds.from_now) do
      assert_not Claim.held_by_other?(@ship, "review", @orpheus), "90 s without a beat and it is stale"
      claim, took = Claim.acquire(@ship, "review", @orpheus)
      assert took
      assert_equal @orpheus, claim.user
    end
  end

  test "take over wins a live claim" do
    Claim.acquire(@ship, "review", @ana)
    claim, took = Claim.acquire(@ship, "review", @orpheus, force: true)
    assert took
    assert_equal @orpheus, claim.reload.user
    assert Claim.held_by_other?(@ship, "review", @ana)
  end
end
