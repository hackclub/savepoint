# One request to a link with UTM tags (D-043): the tags, the path and the time. Nothing that names a person is kept:
# no IP address, user agent or user. The first tags a browser sees also go in a cookie (ApplicationController), and
# sign-up copies them to the user.
class Visit < ApplicationRecord
  TAGS = %w[utm_source utm_medium utm_campaign utm_content utm_term].freeze
  MAX_LENGTH = 100

  # The tags in these request params (or the cookie's hash), cleaned: stripped, lower case, at most 100 characters,
  # nil where blank or missing.
  def self.tags_from(params)
    TAGS.index_with do |tag|
      value = params[tag]
      value.is_a?(String) ? value.strip.downcase.first(MAX_LENGTH).presence : nil
    end
  end

  # The tags kept in the sp_utm cookie's JSON, or none if it's missing or unreadable.
  def self.tags_from_cookie(json)
    parsed = JSON.parse(json.to_s)
    parsed.is_a?(Hash) ? tags_from(parsed) : {}
  rescue JSON::ParserError
    {}
  end
end
