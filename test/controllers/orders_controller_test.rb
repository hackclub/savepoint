require "test_helper"

# POST /shop/order: the claim itself. The shop's page around it is in ShopControllerTest.
class OrdersControllerTest < ActionDispatch::IntegrationTest
  # The shop closed at Program::SHOP_CLOSES_AT. These tests claim prizes, so they run on the last shop day.
  setup { travel_to Time.utc(2026, 11, 9, 12) }

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

  test "D-147: an eligible claim passes, and a claim from someone not eligible is refused" do
    approve(@project, hours: 7)
    sign_in_orpheus(ysws_eligible: false)

    assert_no_difference -> { @project.orders.count } do
      post shop_order_path, params: { order: { prize_key: "micro" } }
    end
    assert_equal OrdersController::NOT_ELIGIBLE, flash[:shop_error]

    sign_in_orpheus(ysws_eligible: true)
    assert_difference -> { @project.orders.count }, 1 do
      post shop_order_path, params: { order: { prize_key: "micro" } }
    end
  end

  test "D-147: the claim asks Hack Club Auth again, so someone verified since sign-in passes and someone since revoked is refused" do
    approve(@project, hours: 7)
    sign_in_orpheus(ysws_eligible: false)
    hca_says({ "ysws_eligible" => true, "verification_status" => "verified" }) do
      assert_difference -> { @project.orders.count }, 1 do
        post shop_order_path, params: { order: { prize_key: "micro" } }
      end
    end
    assert users(:orpheus).reload.ysws_eligible?, "the answer is stored"

    hca_says({ "verification_status" => "pending" }) do
      assert_no_difference -> { @project.orders.count } do
        post shop_order_path, params: { order: { prize_key: "aseprite" } }
      end
    end
    assert_equal OrdersController::NOT_ELIGIBLE, flash[:shop_error]
    assert_not users(:orpheus).reload.ysws_eligible?
  end

  test "D-147: when Hack Club Auth can't be asked, the stored claim decides" do
    approve(@project, hours: 7)
    unavailable = -> { HackClubAuth.singleton_class.alias_method(:__identity, :identity) }
    unavailable.call
    HackClubAuth.define_singleton_method(:identity) { |_user| raise HackClubAuth::Unavailable, "down" }
    begin
      sign_in_orpheus(ysws_eligible: false)
      assert_no_difference -> { @project.orders.count } do
        post shop_order_path, params: { order: { prize_key: "micro" } }
      end
      assert_equal OrdersController::NOT_ELIGIBLE, flash[:shop_error]

      sign_in_orpheus(ysws_eligible: true)
      assert_difference -> { @project.orders.count }, 1 do
        post shop_order_path, params: { order: { prize_key: "micro" } }
      end
    ensure
      HackClubAuth.singleton_class.alias_method(:identity, :__identity)
    end
  end

  test "D-138: a claim works after the end, until the shop closes, and is refused after" do
    approve(@project, hours: 7)
    sign_in_orpheus

    travel_to(Program::ENDS_AT + 2.days) do
      assert_difference -> { @project.orders.count }, 1 do
        post shop_order_path, params: { order: { prize_key: "micro" } }
      end
      assert_equal "micro", flash[:shop_claimed]
      get shop_path
      assert_select ".shop__note", /The shop is open until/
    end

    travel_to(Program::SHOP_CLOSES_AT + 1.minute) do
      assert_no_difference -> { @project.orders.count } do
        post shop_order_path, params: { order: { prize_key: "aseprite" } }
      end
      assert_equal "The shop is closed.", flash[:shop_error]
      get shop_path
      assert_select ".shop-tag__action", 0
      assert_select ".shop__note", /The shop closed/
    end
  end

  test "D-158: a person with a shop extension can claim after the public close, until their own, and others cannot" do
    approve(@project, hours: 7)
    sign_in_orpheus
    @project.update!(shop_until: Program::SHOP_CLOSES_AT + 1.day)

    travel_to(Program::SHOP_CLOSES_AT + 1.hour) do
      assert @project.shop_open?
      get shop_path
      assert_select ".shop__note", /The shop is open until/
      assert_difference -> { @project.orders.count }, 1 do
        post shop_order_path, params: { order: { prize_key: "micro" } }
      end
    end

    travel_to(Program::SHOP_CLOSES_AT + 1.day + 1.minute) do
      assert_not @project.shop_open?
      assert_no_difference -> { @project.orders.count } do
        post shop_order_path, params: { order: { prize_key: "aseprite" } }
      end
      assert_equal "The shop is closed.", flash[:shop_error]
    end

    assert Project.new.shop_open?(Program::SHOP_CLOSES_AT - 1.minute)
    assert_not Project.new.shop_open?(Program::SHOP_CLOSES_AT + 1.minute), "no extension: the public close"
  end

  test "hours waiting for their fraud check can't be spent, and a banned account can't claim (D-063, D-113)" do
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
    # D-113: the ban ends their open session before the claim is looked at, so it never reaches OrdersController::BANNED
    # (which stays, for a claim that lands in the moment between).
    assert_redirected_to root_path
    assert_nil session[:user_id]
    assert_equal ApplicationController::BANNED_ALERT, flash[:alert]
    assert_nil flash[:shop_error]
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
    def sign_in_orpheus(**claims)
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", **claims)
      post "/auth/hackclub"
      follow_redirect!
    end

    # Hack Club Auth's /me answers with this identity inside the block.
    def hca_says(identity)
      HackClubAuth.singleton_class.alias_method(:__identity, :identity)
      HackClubAuth.define_singleton_method(:identity) { |_user| identity }
      yield
    ensure
      HackClubAuth.singleton_class.alias_method(:identity, :__identity)
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
