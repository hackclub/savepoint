# Where a claimed prize ships, as the participant confirms it in the claim step (D-024). It starts from the address Hack
# Club Auth shares (User#address, its address claim) and every field is editable. Whatever they confirm is frozen onto the
# order (Order#address) in Hack Club Auth's own keys, so a later change there never moves a placed order.
class ShippingAddress
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Hack Club Auth's keys, plus a second street line and the phone (optional, for carriers).
  FIELDS = %w[street_address street_address_2 locality region postal_code country phone_number].freeze
  REQUIRED = %w[street_address locality country].freeze
  FIELDS.each { attribute it, :string }

  validates(*REQUIRED, presence: true)
  validates(*FIELDS, length: { maximum: 120 })
  validates :phone_number, format: { with: /\A[+\d\s().-]{5,30}\z/ }, allow_blank: true

  # From the signed-in user: their Hack Club address (its street may hold a second line) and phone.
  def self.for(user)
    from_hash(user.address).tap do |shipping|
      street, *rest = shipping.street_address.to_s.split("\n").map(&:strip).compact_blank
      shipping.street_address = street
      shipping.street_address_2 = shipping.street_address_2.presence || rest.join(", ").presence
      shipping.phone_number = user.phone_number if shipping.phone_number.blank?
    end
  end

  # From a hash, or the JSON of one (a fixture's address is the text of it).
  def self.from_hash(hash)
    hash = JSON.parse(hash) if hash.is_a?(String)
    new(hash.is_a?(Hash) ? hash.stringify_keys.slice(*FIELDS) : {})
  rescue JSON::ParserError
    new
  end

  # One line each: newlines and control characters would break a parcel label.
  def self.from_params(params)
    params = params.permit(*FIELDS) if params.respond_to?(:permit)
    return new unless params.respond_to?(:to_h) && !params.is_a?(String)

    new(params.to_h.stringify_keys.slice(*FIELDS).transform_values { it.to_s.gsub(/[[:cntrl:]]/, " ").squeeze(" ").strip })
  end

  ASKS = { "street_address" => "Add the street address.", "locality" => "Add the city or town.", "country" => "Add the country." }.freeze

  # Each field that's wrong, with plain words for it: { "locality" => "Add the city or town." }.
  def problems
    valid?
    errors.attribute_names.to_h do |name|
      key = name.to_s
      [ key, errors.of_kind?(name, :blank) ? ASKS.fetch(key) : key == "phone_number" ? "Use digits, spaces and + ( ) - only." : "Keep it under 120 characters." ]
    end
  end

  # What the order keeps: the fields they filled in.
  def to_h = attributes.compact_blank
end
