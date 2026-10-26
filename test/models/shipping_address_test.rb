require "test_helper"

class ShippingAddressTest < ActiveSupport::TestCase
  test "it starts from the Hack Club address and phone, a second street line split off" do
    user = users(:orpheus)
    user.update!(address: HQ_ADDRESS.merge("street_address" => "15 Falls Rd\nApt 2\nRear"), phone_number: "+1 802 555 0100")
    shipping = ShippingAddress.for(user)
    assert_equal [ "15 Falls Rd", "Apt 2, Rear", "Shelburne", "VT", "05482", "US", "+1 802 555 0100" ],
                 shipping.attributes.values_at("street_address", "street_address_2", "locality", "region", "postal_code", "country", "phone_number")
    assert shipping.valid?
  end

  test "someone with no address starts empty" do
    user = users(:orpheus)
    user.update!(address: nil, phone_number: nil)
    assert_equal({}, ShippingAddress.for(user).to_h)
  end

  test "street, city and country are needed; region, postal code, second line and phone are not" do
    assert_equal({ "street_address" => "Add the street address.", "locality" => "Add the city or town.", "country" => "Add the country." }, ShippingAddress.new.problems)
    assert_empty ShippingAddress.new(street_address: "1 Elm St", locality: "Leeds", country: "GB").problems
  end

  test "lengths and phone are checked, and params are one tidy line each" do
    assert_equal({ "street_address" => "Keep it under 120 characters.", "phone_number" => "Use digits, spaces and + ( ) - only." },
                 ShippingAddress.new(street_address: "x" * 121, locality: "L", country: "GB", phone_number: "abc").problems)
    shipping = ShippingAddress.from_params(ActionController::Parameters.new(street_address: " 1  Elm\nSt ", other: "x", locality: "L", country: "GB"))
    assert_equal({ "street_address" => "1 Elm St", "locality" => "L", "country" => "GB" }, shipping.to_h)
  end
end
