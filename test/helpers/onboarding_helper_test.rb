require "test_helper"

class OnboardingHelperTest < ActionView::TestCase
  include ApplicationHelper
  include ProjectsHelper

  test "the steps are your game, its Hackatime project, your prize and when you'll build" do
    assert_equal %w[Game Hackatime Prize When], onboarding_steps.map { |step| step[:label] }
  end

  test "the build time tiles are every build time, with when its nudge comes" do
    tiles = onboarding_build_times
    assert_equal Project::BUILD_TIMES, tiles.map { |tile| tile[:value] }
    assert_equal [ "around 3:30", "around 7", "around 9:30", "sat and sun, around 11" ], tiles.map { |tile| tile[:hint] }
  end

  test "the prize cards are every prize, fewest hours first" do
    prizes = onboarding_prizes
    assert_equal Prize::ALL.size, prizes.size
    assert_equal prizes.map(&:hours).sort, prizes.map(&:hours)
    assert_equal "aseprite", prizes.first.key
  end

  test "step 2 says why there's nothing to pick yet, or lists your Hackatime projects" do
    assert_equal({ state: :signed_out }, onboarding_hackatime(nil))
    assert_equal({ state: :unlinked }, onboarding_hackatime(users(:ana)))

    link_hackatime(users(:orpheus))
    choices = onboarding_hackatime(users(:orpheus))
    assert_equal :ready, choices[:state]
    assert_equal Hackatime.stubbed_projects["1001"].map(&:name), choices[:projects].map(&:name)
  end

  test "step 2 leaves out projects with no recent time" do
    link_hackatime(users(:orpheus))
    before = Hackatime.stubbed_recent_projects
    Hackatime.stubbed_recent_projects = { "1001" => [ "dotfiles" ] }
    assert_equal [ "dotfiles" ], onboarding_hackatime(users(:orpheus))[:projects].map(&:name)
  ensure
    Hackatime.stubbed_recent_projects = before
  end
end
