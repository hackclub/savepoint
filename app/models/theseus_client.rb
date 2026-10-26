# The smallest client for Theseus, Hack Club's mail system (D-067): it puts a free sticker order (Order) in a batch
# letter queue, and Hack Club sends the parcels. It goes through Web, so tests set Web.adapter. It never logs or raises an
# address, only a status and an error type.
class TheseusClient
  API = "https://mail.hackclub.com/api/v1"
  DEFAULT_QUEUE = "save-point-stickers"
  BACK_OFFICE = "https://mail.hackclub.com/back_office"

  # The message is for the admin who clicked, so it says what to do, never what was sent.
  class Error < StandardError; end

  # Theseus had a letter for that idempotency key already, so the order was sent before (its id isn't in the answer).
  class AlreadySent < Error; end

  # ENV first (production has no credentials file), then credentials.
  def self.api_key = ENV["THESEUS_API_KEY"].presence || Rails.application.credentials.dig(:theseus, :api_key).presence
  def self.sticker_queue = ENV["THESEUS_STICKER_QUEUE"].presence || Rails.application.credentials.dig(:theseus, :sticker_queue).presence || DEFAULT_QUEUE

  # Where an admin sees the sticker queue, and one letter, in Theseus's back office. A letter id has a "!" in it
  # ("ltr!n43hw55m4"), which is a valid path character, so it stays as it is.
  def self.queue_url = "#{BACK_OFFICE}/letter/queues/#{ERB::Util.url_encode(sticker_queue)}"
  def self.letter_url(id) = "#{BACK_OFFICE}/letters/#{ERB::Util.url_encode(id).gsub("%21", "!")}"

  def initialize(key: self.class.api_key, queue: self.class.sticker_queue)
    raise Error, "Theseus isn't set up: THESEUS_API_KEY is missing" if key.blank?
    @key = key
    @queue = queue
  end

  # Queues the sticker order's letter. Answers the Theseus letter id ("ltr_abc123"). Raises AlreadySent when Theseus
  # has this order's key, and Error for anything else.
  def send_stickers(order)
    user = order.project.user
    body = { address: address(order), recipient_email: user.email.presence, idempotency_key: key_for(order),
             metadata: { save_point_order_id: order.id, save_point_user_id: user.id } }.compact
    response = Web.request(:post, "#{API}/letter_queues/#{ERB::Util.url_encode(@queue)}",
                           headers: { "Authorization" => "Bearer #{@key}", "Content-Type" => "application/json", "Accept" => "application/json" },
                           body: body.to_json, timeout: 20)
    return response.json.fetch("id") if response.ok?

    type = error_type(response)
    raise AlreadySent, "Theseus already has a letter for this order" if type == "idempotency_error"
    raise Error, "Theseus answered #{response.status} #{type}: #{error_messages(response)}".squish.delete_suffix(":")
  rescue Web::Error, JSON::ParserError, KeyError => e
    raise Error, "Theseus could not be reached or answered oddly (#{e.class})"
  end

  def key_for(order) = "save-point_#{Rails.env}_order-#{order.id}_stickers"

  private
    # Hack Club Auth's keys to Theseus's. The country is free text, which Theseus parses.
    def address(order)
      fields = ShippingAddress.from_hash(order.address)
      first, last = split_name(order.recipient_name.presence || order.project.user.recipient_name)
      { first_name: first, last_name: last, line_1: fields.street_address, line_2: fields.street_address_2.presence, city: fields.locality,
        state: fields.region.presence, postal_code: fields.postal_code.presence, country: country_for(fields.country) }.compact
    end

    # Theseus can't parse the UK's constituent countries ("Northern Ireland" got a 422), so they go as ISO "GB".
    # Every other value passes through, since Theseus reads names and ISO codes itself.
    UK_NAMES = [ "northern ireland", "england", "scotland", "wales", "uk", "u.k.", "great britain", "britain" ].freeze

    def country_for(country)
      UK_NAMES.include?(country.to_s.squish.downcase) ? "GB" : country
    end

    # "Ada Byron Lovelace" is Ada Byron and Lovelace. One word is a first name.
    def split_name(name)
      first, _, last = name.to_s.strip.rpartition(" ")
      first.empty? ? [ last, "" ] : [ first, last ]
    end

    def error_type(response)
      error = response.json["error"]
      (error.is_a?(Hash) ? error["type"] : error).to_s.first(60)
    rescue JSON::ParserError
      ""
    end

    # Theseus's validation messages name a field, not a value, so they're safe to show an admin.
    def error_messages(response) = Array(response.json["messages"]).join(", ").first(200)
end
