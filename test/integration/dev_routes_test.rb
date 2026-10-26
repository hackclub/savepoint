require "test_helper"

# The dev tools (fake people, View as) exist only in development.
class DevRoutesTest < ActionDispatch::IntegrationTest
  test "the dev routes are not there outside development" do
    assert_not Rails.env.development?
    assert_not Rails.application.routes.url_helpers.respond_to?(:dev_path)
    assert_not Rails.application.routes.url_helpers.respond_to?(:dev_buddy_path)
    get "/dev"
    assert_response :not_found
    post "/dev/buddy"
    assert_response :not_found
    assert_not Rails.application.routes.url_helpers.respond_to?(:dev_clock_path)
    post "/dev/clock", params: { now: "2026-10-25T12:00:00Z" }
    assert_response :not_found
  end

  test "the dev hours, orders and goal popup controls are not there outside development" do
    urls = Rails.application.routes.url_helpers
    %i[dev_hours_path dev_reset_orders_path dev_reset_goal_popup_path].each { |helper| assert_not urls.respond_to?(helper), helper }
    post "/dev/hours", params: { kind: "logged", percent: 100 }
    assert_response :not_found
    post "/dev/orders/reset"
    assert_response :not_found
    post "/dev/goal_popup/reset"
    assert_response :not_found
  end

  test "the fake hours are pinned only while the fake Hackatime is on" do
    assert_not Hackatime.fake
    assert_raises(RuntimeError) { Dev::MyProject.new(projects(:orpheus)).set_logged!(1) }
  end

  test "the pretend-it's-day-N clock is not in the app outside development" do
    assert_not ApplicationController.include?(DevClock)
    assert_not Time.respond_to?(:travel_to)
  end
end
