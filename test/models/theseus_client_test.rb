require "test_helper"

class TheseusClientTest < ActiveSupport::TestCase
  setup do
    @calls = []
    @order = projects(:ana).orders.new(prize_key: "stickers", hours: 0, address: HQ_ADDRESS.merge("street_address_2" => "Flat 4"), recipient_name: "Ada Byron Lovelace")
    @order.save!(validate: false)
  end

  teardown do
    Web.adapter = nil
    ENV.delete("THESEUS_API_KEY")
    ENV.delete("THESEUS_STICKER_QUEUE")
  end

  def stub(status: 201, body: { id: "ltr_abc123", status: "queued" })
    Web.adapter = lambda do |method, url, headers, payload|
      @calls << [ method, url, headers, JSON.parse(payload) ]
      Web::Response.new(status:, headers: {}, body: body.to_json)
    end
  end

  test "needs a key, and says so" do
    ENV.delete("THESEUS_API_KEY")
    error = assert_raises(TheseusClient::Error) { TheseusClient.new }
    assert_equal "Theseus isn't set up: THESEUS_API_KEY is missing", error.message
  end

  test "the key and queue come from the environment, the queue defaulting to save-point-stickers" do
    ENV["THESEUS_API_KEY"] = "from-env"
    assert_equal "from-env", TheseusClient.api_key
    assert_equal "save-point-stickers", TheseusClient.sticker_queue
    ENV["THESEUS_STICKER_QUEUE"] = "other"
    assert_equal "other", TheseusClient.sticker_queue
  end

  test "posts the letter to the queue and answers its id" do
    stub
    assert_equal "ltr_abc123", TheseusClient.new(key: "k", queue: "save-point-stickers").send_stickers(@order)

    method, url, headers, body = @calls.first
    assert_equal :post, method
    assert_equal "https://mail.hackclub.com/api/v1/letter_queues/save-point-stickers", url
    assert_equal "Bearer k", headers["Authorization"]
    assert_equal({ "first_name" => "Ada Byron", "last_name" => "Lovelace", "line_1" => "15 Falls Rd", "line_2" => "Flat 4", "city" => "Shelburne",
                   "state" => "VT", "postal_code" => "05482", "country" => "US" }, body["address"])
    assert_equal "ana@hackclub.com", body["recipient_email"]
    assert_equal "save-point_test_order-#{@order.id}_stickers", body["idempotency_key"]
    assert_equal({ "save_point_order_id" => @order.id, "save_point_user_id" => users(:ana).id }, body["metadata"])
  end

  test "a one-word name is a first name with no last name" do
    @order.update!(recipient_name: "Ada")
    stub
    TheseusClient.new(key: "k").send_stickers(@order)
    assert_equal [ "Ada", "" ], @calls.first.last["address"].values_at("first_name", "last_name")
  end

  test "an idempotency error means it was sent already" do
    stub(status: 400, body: { error: "idempotency_error", messages: [ "used" ] })
    assert_raises(TheseusClient::AlreadySent) { TheseusClient.new(key: "k").send_stickers(@order) }
  end

  test "other errors name the status, type and messages, never the address" do
    stub(status: 422, body: { error: "validation_error", messages: [ "Address country is invalid" ] })
    error = assert_raises(TheseusClient::Error) { TheseusClient.new(key: "k").send_stickers(@order) }
    assert_equal "Theseus answered 422 validation_error: Address country is invalid", error.message
    assert_no_match(/Falls/, error.message)
  end

  test "a network failure is an error too" do
    Web.adapter = ->(*) { raise Web::Error, "boom" }
    assert_raises(TheseusClient::Error) { TheseusClient.new(key: "k").send_stickers(@order) }
  end
end
