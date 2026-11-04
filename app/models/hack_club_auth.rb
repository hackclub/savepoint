require "net/http"

# Hack Club Auth's /me, asked with the access token kept at sign-in (refreshed once on a 401), the way Playground refreshes a
# person's verification at submit and redeem. D-147: Save Point reads ysws_eligible from it when a prize is claimed and when a ship
# goes to the Unified YSWS DB.
module HackClubAuth
  SITE = "https://auth.hackclub.com".freeze

  # HCA couldn't be asked, or answered something we can't use. Callers fall back to the stored values.
  class Unavailable < StandardError; end

  # The person's identity hash from /me ("ysws_eligible", "verification_status", ...). Raises Unavailable.
  def self.identity(user)
    raise Unavailable, "no token" if user.hca_access_token.blank?

    response = get_me(user.hca_access_token)
    if response.is_a?(Net::HTTPUnauthorized) && user.hca_refresh_token.present?
      refresh!(user)
      response = get_me(user.hca_access_token)
    end
    raise Unavailable, "Hack Club Auth answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("identity")
  rescue JSON::ParserError, KeyError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
    raise Unavailable, error.message
  end

  def self.get_me(token)
    uri = URI("#{SITE}/api/v1/me")
    request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{token}", "Accept" => "application/json")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5) { it.request(request) }
  end

  def self.refresh!(user)
    uri = URI("#{SITE}/oauth/token")
    credentials = ->(key) { Rails.application.credentials.dig(:hack_club_auth, key) || ENV["HACK_CLUB_AUTH_#{key.upcase}"] }
    request = Net::HTTP::Post.new(uri)
    request.set_form_data(grant_type: "refresh_token", refresh_token: user.hca_refresh_token,
                          client_id: credentials.(:client_id), client_secret: credentials.(:client_secret))
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5) { it.request(request) }
    raise Unavailable, "token refresh answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    user.update!(hca_access_token: body.fetch("access_token"), hca_refresh_token: body["refresh_token"].presence || user.hca_refresh_token)
  end
end
