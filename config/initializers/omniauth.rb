# Sign-in with Hack Club Auth, over OpenID Connect: https://auth.hackclub.com/docs/oidc-guide
#
# Register the app at https://auth.hackclub.com/developer/apps with the redirect URI below, then set the
# client ID and secret in credentials (hack_club_auth: client_id, client_secret) or the environment.
hack_club_auth = ->(key) { Rails.application.credentials.dig(:hack_club_auth, key) || ENV["HACK_CLUB_AUTH_#{key.upcase}"] }
# Linking Hackatime, over OAuth2 (like Stardance does): register the app on Hackatime with the redirect URI
# <this site>/auth/hackatime/callback, then set hackatime: client_id, client_secret (or HACKATIME_CLIENT_ID/SECRET).
hackatime = ->(key) { Rails.application.credentials.dig(:hackatime, key) || ENV["HACKATIME_#{key.upcase}"] }

# Whether Save Point has a Hackatime OAuth app: the onboarding "Link Hackatime" button needs only this.
Rails.application.config.x.hackatime_configured = hackatime.(:client_id).present?
# Sign-in chains on to Hackatime (D-026) only when that app is set up AND HACKATIME_CHAIN=1. The switch exists because
# a HACKATIME_CLIENT_ID in production may not belong to a working Hackatime app, and the chain would then send every
# new sign-in into a failing step. Turn it on once the app is confirmed. Tests turn it on per test.
Rails.application.config.x.hackatime_chain =
  Rails.application.config.x.hackatime_configured && ENV["HACKATIME_CHAIN"] == "1"

# OmniAuth's OAuth2 callback URL carries the request's query string along, so it'd stop matching the redirect URI
# registered with Hackatime (and the token exchange would fail). Send just the path.
OmniAuth::Strategies::OAuth2.class_eval do
  def callback_url
    full_host + callback_path
  end
end

# Every scope Hack Club Auth has: Save Point's an HQ official app, so it may ask for phone, address and birthdate too
# (community apps can't). slack_id and verification_status add those claims (and ysws_eligible). The address posts
# prizes; it, the phone and the birthdate go with a ship's submission.
Rails.application.config.x.hack_club_auth_scopes = %i[openid profile email phone address birthdate slack_id verification_status]

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :openid_connect,
    name: :hackclub,
    issuer: "https://auth.hackclub.com",
    discovery: true,
    response_type: :code,
    scope: Rails.configuration.x.hack_club_auth_scopes,
    client_options: {
      identifier: hack_club_auth.(:client_id),
      secret: hack_club_auth.(:client_secret),
      # This site's own callback unless set: savepoint.hackclub.com (or APP_URL) in production, localhost elsewhere.
      redirect_uri: hack_club_auth.(:redirect_uri) ||
        "#{Rails.env.production? ? ENV.fetch("APP_URL", "https://savepoint.hackclub.com") : "http://localhost:3000"}/auth/hackclub/callback"
    }

  # Not a way to sign in: once you're signed in, it links your Hackatime (see HackatimeLinksController).
  provider :oauth2, hackatime.(:client_id), hackatime.(:client_secret),
    name: :hackatime,
    scope: "profile read",
    client_options: {
      site: ENV.fetch("HACKATIME_URL", "https://hackatime.hackclub.com"),
      authorize_url: "/oauth/authorize",
      token_url: "/oauth/token"
    }
end

OmniAuth.config.logger = Rails.logger

# Hack Club Auth's whoami (https://github.com/hackclub/auth/pull/279): the browser asks it, with HCA's own
# session cookie, for the first name of someone signed in to HCA but not to us yet, so the pledge can be signed
# in their name before OAuth. An HCA admin enables it for our app and allowlists this site's origin; it only
# sees HCA's cookie from a hackclub.com subdomain, and answers nothing anywhere else.
Rails.application.config.x.hack_club_auth_whoami_url =
  ENV.fetch("HACK_CLUB_AUTH_WHOAMI_URL", "https://auth.hackclub.com/api/external/whoami")
