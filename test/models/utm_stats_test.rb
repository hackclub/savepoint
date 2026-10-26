require "test_helper"

# Where sign-ups come from (D-043): only landing-page visits count, since every page view is a Visit (D-047, D-058).
class UtmStatsTest < ActiveSupport::TestCase
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    users(:ana).update!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch")
    3.times { Visit.create!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch", path: "/") }
    Visit.create!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch", path: "/project")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "tagged rows count landing visits and sign-ups" do
    row = UtmStats.new.rows.sole
    assert_equal [ "slack", "post", "launch", 3, 1 ], [ row.source, row.medium, row.campaign, row.visits, row.signups ]
    assert_in_delta 33.3, row.rate, 0.1
  end

  test "untagged visits off the landing page are not counted, and there is no all-nil row" do
    4.times { Visit.create!(path: "/project") }
    Visit.create!(path: "/start")
    stats = UtmStats.new

    assert_equal 0, stats.untagged_visits
    assert_equal [ [ "slack", "post", "launch" ] ], stats.rows.map { [ it.source, it.medium, it.campaign ] }
  end

  test "the No tags figures are the untagged landing visits, the untagged sign-ups and their rate" do
    2.times { Visit.create!(path: "/") }
    Visit.create!(path: "/project")
    stats = UtmStats.new

    assert_equal 2, stats.untagged_visits
    assert_equal User.participants.where(utm_source: nil).count, stats.untagged
    assert_in_delta 100.0 * stats.untagged / 2, stats.untagged_rate, 0.01
    assert_predicate stats, :any?
  end

  test "a visit with only utm_content set is tagged, not untagged" do
    Visit.create!(utm_content: "banner", path: "/")
    assert_equal 0, UtmStats.new.untagged_visits
  end

  test "with no untagged landing visits there is no rate" do
    assert_nil UtmStats.new.untagged_rate
  end
end
