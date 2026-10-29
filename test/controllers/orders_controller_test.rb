require "test_helper"

# POST /shop/order: the claim itself. The shop's page around it is in ShopControllerTest.
class OrdersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ADMIN" ]
    @project = projects(:orpheus)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "a claim within the approved hours is saved, and one over them is refused" do
    approve(@project, hours: 7)
    sign_in_orpheus

    assert_difference -> { @project.orders.count }, 1 do
      post shop_order_path, params: { order: { prize_key: "micro" } }
    end
    assert_redirected_to shop_path
    assert_equal "micro", flash[:shop_claimed]

    assert_no_difference -> { @project.orders.count } do
      post shop_order_path, params: { order: { prize_key: "aseprite" } }
    end
    assert_redirected_to shop_path
    assert_equal "That's 5 hours, and you've 0.5 approved to spend.", flash[:shop_error]
  end

  test "hours waiting for their fraud check can't be spent, and a banned account can't claim (D-063)" do
    ship = approve(@project, hours: 7)
    ship.update_columns(status: "awaiting_fraud", fraud_status: "pending", approved_hours: nil, review_hours: 7)
    sign_in_orpheus

    assert_no_difference -> { @project.orders.count } do
      post shop_order_path, params: { order: { prize_key: "micro" } }
    end
    assert_match(/0 approved to spend/, flash[:shop_error])

    ship.update_columns(approved_columns(7))
    users(:orpheus).update_columns(banned_at: Time.current, ban_reason: "Fraud.")
    assert_no_difference -> { @project.orders.count } do
      post shop_order_path, params: { order: { prize_key: "micro" } }
    end
    assert_equal OrdersController::BANNED, flash[:shop_error]
  end

  # Stands in for a claim that got in first: it runs as the project's lock is asked for, so before the lock is held.
  module RivalBeforeLock
    mattr_accessor :rival

    def with_lock(*)
      rival&.call(self)
      super
    end
  end
  Project.prepend(RivalBeforeLock)

  test "a claim reads the hours left inside the project's lock, so one made while it waited is counted" do
    approve(@project, hours: 7)
    sign_in_orpheus
    RivalBeforeLock.rival = lambda do |project|
      RivalBeforeLock.rival = nil
      Order.insert!({ project_id: project.id, prize_key: "aseprite", hours: 5, status: "waiting", created_at: Time.current, updated_at: Time.current })
    end

    assert_no_difference -> { @project.orders.where(prize_key: "micro").count } do
      post shop_order_path, params: { order: { prize_key: "micro" } }
    end
    assert_match(/approved to spend\.\z/, flash[:shop_error])
  ensure
    RivalBeforeLock.rival = nil
  end

  private
    def sign_in_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end

    def approve(project, hours:)
      travel_to(Program::STARTS_AT + 2.days) do
        project.user.streak_activities.find_or_initialize_by(activity_date: (Program::STARTS_AT + 1.day).to_date).update!(coded_seconds: (hours * 3600).to_i)
        project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, and it is a game.",
                              repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours:,
                              screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
                .tap { approve_through_fraud(it) }
      end
    end
end
