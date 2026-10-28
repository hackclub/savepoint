require "test_helper"

class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @order = projects(:ana).orders.new(prize_key: "micro", hours: 6.5, address: HQ_ADDRESS)
    @order.save!(validate: false) # as if their approved hours covered it
  end

  teardown do
    Rails.configuration.x.admin_slack_ids = @admins
    Web.adapter = nil
    ENV.delete("THESEUS_API_KEY")
  end

  test "the queue shows the second street line and the phone they gave, for the carrier" do
    @order.update!(address: HQ_ADDRESS.merge("street_address_2" => "Flat 4", "phone_number" => "+1 802 555 0123"))
    sign_in_as(users(:orpheus))
    get admin_orders_path

    assert_select "tr##{dom_id(@order)} .admin__address", /15 Falls Rd\s+Flat 4\s+Shelburne, VT 05482\s+US/
    assert_select "tr##{dom_id(@order)} .pg-admin-orders__phone", "Phone +1 802 555 0123"
  end

  test "admins see what's to order and mark it ordered" do
    sign_in_as(users(:orpheus))
    get admin_orders_path

    assert_response :success
    assert_select ".pg-admin-orders__count", /1 to order/
    assert_select ".admin__nav a[aria-current=page]", "Orders"
    assert_select "tr##{dom_id(@order)}", text: /Ana Lovelace.*ana@hackclub\.com.*8BitDo Micro.*Pocket controller.*6\.5 hrs/m
    assert_select "tr##{dom_id(@order)} .admin__address", /15 Falls Rd\s+Shelburne, VT 05482\s+US/

    patch admin_order_path(@order)
    assert_redirected_to admin_orders_path
    assert @order.reload.ordered?
    assert_equal users(:orpheus), @order.ordered_by
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_match(/Your 8BitDo Micro is ordered, yay/, dm[:args].second)

    follow_redirect!
    assert_select ".pg-admin-orders__count", /0 to order/
    assert_select "tr##{dom_id(@order)} form", 0
    assert_select "tr##{dom_id(@order)} [data-decision=approved]", /Orpheus/

    patch admin_order_path(@order)
    assert_equal "That one's been ordered already.", flash[:alert]
  end

  test "the parcel is for the recipient name, with the Hack Club name beside it to check" do
    @order.update!(recipient_name: "Ada Byron")
    sign_in_as(users(:orpheus))
    get admin_orders_path
    assert_select "tr##{dom_id(@order)} .pg-admin-orders__recipient", /To Ada Byron \(Hack Club: Ana Lovelace\)/

    @order.update!(recipient_name: "Ana Lovelace")
    get admin_orders_path
    assert_select "tr##{dom_id(@order)} .pg-admin-orders__recipient", /To Ana Lovelace\s*\z/
  end

  test "nobody else can see it, or order" do
    get admin_orders_path
    assert_response :not_found

    sign_in_as(users(:ana))
    patch admin_order_path(@order)
    assert_response :not_found
    assert @order.reload.waiting?
  end

  test "a sticker order shows Ship, and shipping it orders it with the letter id and DMs them" do
    ENV["THESEUS_API_KEY"] = "k"
    sticker = make_sticker(projects(:ana))
    calls = stub_theseus(body: { id: "ltr_abc123" })
    sign_in_as(users(:orpheus))
    get admin_orders_path
    assert_select "tr##{dom_id(sticker)} button", /\A\s*Ship\s*\z/
    assert_select "tr##{dom_id(@order)} button", /Mark ordered/
    assert_select "form[action='#{send_stickers_admin_orders_path}'] button", /Ship all waiting stickers \(1\)/

    patch admin_order_path(sticker)
    assert_redirected_to admin_orders_path
    assert sticker.reload.ordered?
    assert_equal [ "ltr_abc123", users(:orpheus) ], [ sticker.theseus_letter_id, sticker.ordered_by ]
    assert_equal 1, calls.size
    assert_equal "Your stickers are on their way! :yayayayayay:", enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }[:args].second

    follow_redirect!
    assert_select "tr##{dom_id(sticker)} .pg-admin-orders__letter code", "ltr_abc123"
    assert_select "form[action='#{send_stickers_admin_orders_path}']", 0
  end

  test "the Theseus queue link shows when there is a sticker order, and not otherwise" do
    sign_in_as(users(:orpheus))
    get admin_orders_path
    assert_select "a[href*='back_office']", 0

    sticker = make_sticker(projects(:ana))
    get admin_orders_path
    assert_select "a[href='https://mail.hackclub.com/back_office/letter/queues/save-point-stickers'][target=_blank][rel=noopener]", "Open the Theseus queue"

    sticker.update!(status: "ordered", ordered_at: Time.current, ordered_by: users(:orpheus), theseus_letter_id: "ltr!n43hw55m4")
    get admin_orders_path
    assert_select "a", text: "Open the Theseus queue"
    assert_select "form[action='#{send_stickers_admin_orders_path}']", 0
  end

  test "a sticker row links to the project it was earned on, and a plain prize row does not" do
    sticker = make_sticker(projects(:ana))
    sign_in_as(users(:orpheus))
    get admin_orders_path
    assert_select "tr##{dom_id(sticker)} .pg-admin-orders__project a[href='#{admin_project_path(projects(:ana))}']", projects(:ana).title
    assert_select "tr##{dom_id(@order)} .pg-admin-orders__project", 0
  end

  test "a shipped sticker row links its letter id to Theseus" do
    sticker = make_sticker(projects(:ana))
    sticker.update!(status: "ordered", ordered_at: Time.current, ordered_by: users(:orpheus), theseus_letter_id: "ltr!n43hw55m4")
    sign_in_as(users(:orpheus))
    get admin_orders_path
    assert_select "tr##{dom_id(sticker)} .pg-admin-orders__project a", projects(:ana).title
    assert_select "tr##{dom_id(sticker)} .pg-admin-orders__letter a[href='https://mail.hackclub.com/back_office/letters/ltr!n43hw55m4'][target=_blank][rel=noopener] code", "ltr!n43hw55m4"
  end

  test "a plain prize never goes to Theseus" do
    calls = stub_theseus
    sign_in_as(users(:orpheus))
    patch admin_order_path(@order)
    assert @order.reload.ordered?
    assert_nil @order.theseus_letter_id
    assert_empty calls
  end

  test "with no key, Ship says so and changes nothing" do
    ENV.delete("THESEUS_API_KEY")
    sticker = make_sticker(projects(:ana))
    sign_in_as(users(:orpheus))
    patch admin_order_path(sticker)
    assert_equal "Theseus isn't set up: THESEUS_API_KEY is missing", flash[:alert]
    assert sticker.reload.waiting?
    assert_no_enqueued_jobs only: SlackMessageJob
  end

  test "when Theseus refuses a sticker order it stays waiting and the admin sees why" do
    ENV["THESEUS_API_KEY"] = "k"
    sticker = make_sticker(projects(:ana))
    stub_theseus(status: 422, body: { error: "validation_error", messages: [ "Address country is invalid" ] })
    sign_in_as(users(:orpheus))
    patch admin_order_path(sticker)
    assert_equal "Theseus answered 422 validation_error: Address country is invalid", flash[:alert]
    assert sticker.reload.waiting?
  end

  test "an idempotency error marks the sticker order ordered with no letter id, and says so" do
    ENV["THESEUS_API_KEY"] = "k"
    sticker = make_sticker(projects(:ana))
    stub_theseus(status: 400, body: { error: "idempotency_error", messages: [ "used" ] })
    sign_in_as(users(:orpheus))
    patch admin_order_path(sticker)
    assert sticker.reload.ordered?
    assert_nil sticker.theseus_letter_id
    assert_equal "Shipped, but Theseus had it already, so there's no letter ID.", flash[:notice]
  end

  test "Ship all ships every waiting sticker order, reports the count, and names the ones that failed" do
    ENV["THESEUS_API_KEY"] = "k"
    good = make_sticker(projects(:ana))
    bad = make_sticker(projects(:orpheus))
    Web.adapter = lambda do |_method, _url, _headers, payload|
      failing = JSON.parse(payload)["metadata"]["save_point_order_id"] == bad.id
      Web::Response.new(status: failing ? 422 : 201, headers: {}, body: (failing ? { error: "validation_error", messages: [ "bad" ] } : { id: "ltr_#{good.id}" }).to_json)
    end
    sign_in_as(users(:orpheus))
    post send_stickers_admin_orders_path
    assert_redirected_to admin_orders_path
    assert_match(/\AShipped 1 sticker order\. Failed: order #{bad.id} \(Theseus answered 422 validation_error: bad\)\.\z/, flash[:alert])
    assert good.reload.ordered?
    assert bad.reload.waiting?
    assert @order.reload.waiting?
  end

  test "Ship refuses a sticker order for a banned account and sends nothing" do
    ENV["THESEUS_API_KEY"] = "k"
    sticker = make_sticker(projects(:ana))
    calls = stub_theseus
    link_hackatime(users(:ana))
    Hackatime.stubbed_trust_levels = { users(:ana).hackatime_uid => "red" }
    sign_in_as(users(:orpheus))
    patch admin_order_path(sticker)
    assert_equal "Not sent: Hackatime has banned this account", flash[:alert]
    assert sticker.reload.waiting?
    assert_empty calls
  ensure
    Hackatime.stubbed_trust_levels = {}
  end

  test "Ship refuses a sticker order for an account that isn't YSWS-eligible" do
    ENV["THESEUS_API_KEY"] = "k"
    sticker = make_sticker(projects(:ana))
    users(:ana).update_column(:ysws_eligible, false)
    calls = stub_theseus
    sign_in_as(users(:orpheus))
    patch admin_order_path(sticker)
    assert_equal "Not sent: this account isn't YSWS-eligible", flash[:alert]
    assert sticker.reload.waiting?
    assert_empty calls
  end

  test "Ship waits when Hackatime can't say" do
    ENV["THESEUS_API_KEY"] = "k"
    sticker = make_sticker(projects(:ana))
    calls = stub_theseus
    link_hackatime(users(:ana))
    Hackatime.stubbed_trust_levels = { users(:ana).hackatime_uid => :unavailable }
    sign_in_as(users(:orpheus))
    patch admin_order_path(sticker)
    assert_equal "Not sent: couldn't reach Hackatime to check this account", flash[:alert]
    assert sticker.reload.waiting?
    assert_empty calls
  ensure
    Hackatime.stubbed_trust_levels = {}
  end

  test "Ship all skips ineligible accounts, keeps them waiting, and names them" do
    ENV["THESEUS_API_KEY"] = "k"
    good = make_sticker(projects(:ana))
    banned = make_sticker(projects(:orpheus))
    link_hackatime(users(:orpheus))
    Hackatime.stubbed_trust_levels = { users(:orpheus).hackatime_uid => "red" }
    stub_theseus
    sign_in_as(users(:orpheus))
    post send_stickers_admin_orders_path
    assert_equal "Shipped 1 sticker order. Not sent, still waiting: order #{banned.id} (Hackatime has banned this account).", flash[:alert]
    assert good.reload.ordered?
    assert banned.reload.waiting?
  ensure
    Hackatime.stubbed_trust_levels = {}
  end

  test "Ship all is for admins only" do
    sign_in_as(users(:ana))
    post send_stickers_admin_orders_path
    assert_response :not_found
  end

  private
    def link_hackatime(user)
      user.update!(hackatime_uid: "hk#{user.id}", hackatime_access_token: "token")
    end

    def make_sticker(project)
      project.orders.new(prize_key: "stickers", hours: 0, address: HQ_ADDRESS).tap { it.save!(validate: false) }
    end

    def stub_theseus(status: 201, body: { id: "ltr_x" })
      calls = []
      Web.adapter = lambda do |*args|
        calls << args
        Web::Response.new(status:, headers: {}, body: body.to_json)
      end
      calls
    end

    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
