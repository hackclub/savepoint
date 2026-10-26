require "test_helper"
require Rails.root.join("db/migrate/20261023150000_create_insights_views")
require Rails.root.join("db/migrate/20261023160100_add_utm_to_insights_views")
require Rails.root.join("db/migrate/20261024100100_add_last_seen_to_insights_users")
require Rails.root.join("db/migrate/20261024130100_add_onboarding_progress_to_insights_users")
require Rails.root.join("db/migrate/20261024110100_add_hackatime_seen_to_insights_projects")
require Rails.root.join("db/migrate/20261026100100_update_insights_ships_for_fraud_stage")

# The views the analytics service reads (hackclub/save-point-analytics). The test database loads from schema.rb,
# which doesn't dump views, so the migration runs here when they're absent. The test's transaction rolls it back.
class InsightsViewsTest < ActiveSupport::TestCase
  VIEWS = (CreateInsightsViews::VIEWS + %w[visits]).freeze
  FORBIDDEN = %w[email name address phone_number birthdate slack_id hackatime_access_token].freeze

  setup do
    connection = ActiveRecord::Base.connection
    present = connection.select_values("select viewname from pg_views where schemaname = 'insights'")
    return if (VIEWS - present).empty?

    ActiveRecord::Migration.suppress_messages do
      CreateInsightsViews.new.up
      AddUtmToInsightsViews.new.up
      AddLastSeenToInsightsUsers.new.up
      AddOnboardingProgressToInsightsUsers.new.up
      AddHackatimeSeenToInsightsProjects.new.up
      UpdateInsightsShipsForFraudStage.new.up
    end
  end

  test "the six views exist" do
    present = ActiveRecord::Base.connection.select_values("select viewname from pg_views where schemaname = 'insights'")
    assert_equal VIEWS.sort, present.sort
  end

  test "no view exposes a person's details or a token" do
    columns = ActiveRecord::Base.connection.select_rows(
      "select table_name, column_name from information_schema.columns where table_schema = 'insights'"
    )
    assert_not_empty columns
    columns.each do |view, column|
      assert_not_includes FORBIDDEN, column, "insights.#{view} exposes #{column}"
      assert_not column.end_with?("_token"), "insights.#{view} exposes #{column}"
    end
  end

  test "the views can be read" do
    VIEWS.each { |view| ActiveRecord::Base.connection.select_rows("select * from insights.#{view} limit 1") }
    hash = ActiveRecord::Base.connection.select_value("select slack_hash from insights.users limit 1")
    assert_match(/\A\h{64}\z/, hash) if hash
  end

  test "the UTM tags are in insights.users and insights.visits (D-043)" do
    users(:ana).update!(utm_source: "slack", utm_medium: "post", utm_campaign: "launch")
    Visit.create!(utm_source: "slack", path: "/")
    connection = ActiveRecord::Base.connection

    assert_equal %w[slack post launch], connection.select_rows("select utm_source, utm_medium, utm_campaign from insights.users where user_id = #{users(:ana).id}").first
    assert_equal %w[slack /], connection.select_rows("select utm_source, path from insights.visits").first
    assert_equal %w[created_at path utm_campaign utm_content utm_medium utm_source utm_term visit_id],
                 connection.select_values("select column_name from information_schema.columns where table_schema = 'insights' and table_name = 'visits'").sort
  end

  test "the UTM migration reverses" do
    ActiveRecord::Migration.suppress_messages do
      AddUtmToInsightsViews.new.down
      assert_equal %w[orders projects ships streak_activities users], ActiveRecord::Base.connection.select_values("select viewname from pg_views where schemaname = 'insights'").sort
      AddUtmToInsightsViews.new.up
    end
  end

  test "insights.users shows when and where a participant was last seen (D-047)" do
    users(:ana).update_columns(last_seen_at: Time.zone.parse("2026-10-24 10:00"), last_seen_path: "/project")
    row = ActiveRecord::Base.connection.select_rows("select last_seen_at, last_seen_path from insights.users where user_id = #{users(:ana).id}").first

    assert_equal "/project", row.last
    assert_equal Time.zone.parse("2026-10-24 10:00"), Time.zone.parse(row.first.to_s + " UTC")
  end

  test "insights.users shows how far a participant got through onboarding" do
    users(:ana).update_columns(onboarding_step_reached: 4, onboarding_step_at: Time.utc(2026, 10, 24, 10))
    columns = ActiveRecord::Base.connection.select_values("select column_name from information_schema.columns where table_schema = 'insights' and table_name = 'users' order by ordinal_position")
    row = ActiveRecord::Base.connection.select_rows("select onboarding_step_reached, onboarding_step_at from insights.users where user_id = #{users(:ana).id}").first

    assert_equal %w[onboarding_step_reached onboarding_step_at], columns.last(2)
    assert_equal 4, row.first
    assert_not_nil row.last
  end

  test "the onboarding progress migration reverses" do
    ActiveRecord::Migration.suppress_messages do
      AddOnboardingProgressToInsightsUsers.new.down
      columns = ActiveRecord::Base.connection.select_values("select column_name from information_schema.columns where table_schema = 'insights' and table_name = 'users'")
      assert_not_includes columns, "onboarding_step_reached"
      assert_includes columns, "last_seen_at"
      AddOnboardingProgressToInsightsUsers.new.up
    end
  end

  test "the last seen migration reverses" do
    ActiveRecord::Migration.suppress_messages do
      AddOnboardingProgressToInsightsUsers.new.down
      AddLastSeenToInsightsUsers.new.down
      columns = ActiveRecord::Base.connection.select_values("select column_name from information_schema.columns where table_schema = 'insights' and table_name = 'users'")
      assert_not_includes columns, "last_seen_at"
      assert_includes columns, "utm_source"
      AddLastSeenToInsightsUsers.new.up
      AddOnboardingProgressToInsightsUsers.new.up
    end
  end

  test "insights.projects shows what Hackatime showed the participant, as counts and seconds" do
    project = projects(:ana)
    connection = ActiveRecord::Base.connection
    row = -> { connection.select_rows("select hackatime_baseline_count, hackatime_seen_count, hackatime_seen_seconds, hackatime_seen_at from insights.projects where project_id = #{project.id}").first }

    assert_equal [ nil, nil, nil, nil ], row.call, "nothing known yet"

    project.update_columns(hackatime_baseline: [ "a", "b" ], hackatime_seen_count: 3, hackatime_seen_seconds: 5400, hackatime_seen_at: Time.utc(2026, 10, 24, 9))
    count, seen, seconds, at = row.call
    assert_equal [ 2, 3, 5400 ], [ count, seen, seconds ]
    assert_not_nil at
  end

  test "insights.ships keeps its statuses, with the fraud stage as in review, and gains a stage (D-063)" do
    connection = ActiveRecord::Base.connection
    ship = projects(:ana).ships.create!(title: "Pong", description: "Two paddles, one ball, and every frame is a sprite.", repo_url: "https://github.com/ana/pong",
                                        demo_url: "https://example.com/pong", hours: 5, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                                        screenshot_shows_game: true)
    row = -> { connection.select_rows("select status, stage from insights.ships where ship_id = #{ship.id}").first }

    assert_equal %w[in_review in_review], row.call
    ship.update_columns(status: "awaiting_fraud")
    assert_equal %w[in_review awaiting_fraud], row.call, "to the analytics it is still in review"
    ship.update_columns(status: "changes_needed")
    assert_equal %w[rejected changes_needed], row.call
    ship.update_columns(status: "rejected")
    assert_equal %w[rejected rejected], row.call
    ship.update_columns(status: "approved")
    assert_equal %w[approved approved], row.call
  end
end
