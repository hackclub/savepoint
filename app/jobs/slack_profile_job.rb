# What we take from someone's Slack profile: their display name and username (the handle, Slack's user.name), which is
# what everyone else here sees them as (User#public_name, D-012), their profile picture (only a custom one; Slack's default placeholder is left out), and their timezone, for when their browser hasn't told us (the browser wins whenever it does;
# see ApplicationController#remember_timezone). Never their real name: Slack shows that when the display name is
# blank, so we leave it blank and the username stands in. Run at sign-in and daily (SlackProfilesSyncJob). Needs the bot's users:read scope.
class SlackProfileJob < ApplicationJob
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: 30.seconds, attempts: 5

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil? || user.slack_id.blank?
    return Rails.logger.info("Slack (not configured): would look up #{user.slack_id}'s profile") unless Rails.configuration.x.slack_configured

    slack_user = Slack::Web::Client.new.users_info(user: user.slack_id).user
    profile = slack_user["profile"] || {}
    # Slack's default picture is a placeholder, so only a custom image counts as their picture.
    avatar_url = profile["image_512"].to_s.strip.presence if profile["is_custom_image"]
    user.update!(slack_display_name: profile["display_name"].to_s.strip.presence,
                 slack_username: slack_user["name"].to_s.strip.presence,
                 slack_avatar_url: avatar_url)
    user.remember_timezone(slack_user["tz"]) if user.timezone.blank?
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
  rescue Slack::Web::Api::Errors::SlackError => error
    Rails.logger.warn("Looking up #{user.slack_id}'s Slack profile failed: #{error.message}")
  end
end
