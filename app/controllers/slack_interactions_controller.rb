# Slack posts here when someone clicks a button in one of our messages. The "Join" link button in an announcement
# (lib/slack_announcement.rb) still sends a block_actions payload, and without a 200 Slack warns that the app can't
# handle interactive responses. The link opens on its own, so this does nothing: it doesn't read the payload, which
# holds Slack user IDs.
#
# It inherits ActionController::API, not ApplicationController, because it answers Slack's server and never a browser
# session. The API base has no cookies, session or CSRF protection, and none of the app's before_actions (timezone,
# UTM attribution), so nothing can create a user or a Visit or set a cookie.
class SlackInteractionsController < ActionController::API
  def create
    head :ok
  end
end
