# Adds someone to Save Point's Slack channels (Program::SLACK_CHANNEL_IDS, D-028), once their Slack is linked. Sign-in
# starts it, and JoinSlackChannelsSweepJob catches everyone else. Once it has worked, it isn't tried again.
# (Like Stardance's InviteToSlackChannelJob.)
#
# Returns :joined, :failed or :blocked (nil when it did nothing). The three outcomes of a Slack error:
# - already_in_channel counts as joined.
# - A reason about this person that won't change (PERSON_ERRORS): slack_channels_failed_at is set, so the sweep skips
#   them. Signing in again tries once more.
# - Anything else (a missing scope, including channels:join; a Slack outage) is about us, not them. Nobody is marked,
#   and the sweep stops its run so it doesn't hammer Slack.
# If the bot isn't in the channel (not_in_channel), it joins it first and invites again (SlackBot.joining).
class JoinSlackChannelsJob < ApplicationJob
  PERSON_ERRORS = %w[user_is_restricted cant_invite cant_invite_self user_not_found user_disabled].freeze

  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: 30.seconds, attempts: 3

  def perform(user_id)
    return if Program::SLACK_CHANNEL_IDS.empty?

    user = User.find_by(id: user_id)
    return if user.nil? || user.slack_id.blank? || user.slack_channels_joined_at
    return Rails.logger.info("Slack (not configured): would add #{user.slack_id} to #{Program::SLACK_CHANNEL_IDS.join(", ")}") unless Rails.configuration.x.slack_configured

    client = Slack::Web::Client.new
    results = Program::SLACK_CHANNEL_IDS.map do |channel|
      SlackBot.joining(client, channel) { client.conversations_invite(channel:, users: user.slack_id) }
      :joined
    rescue Slack::Web::Api::Errors::TooManyRequestsError
      raise
    rescue Slack::Web::Api::Errors::SlackError => error
      next :joined if error.message == "already_in_channel"
      Rails.logger.warn("Adding #{user.slack_id} to Slack channel #{channel} failed: #{error.message}")
      PERSON_ERRORS.include?(error.message) ? :failed : :blocked
    end

    if results.include?(:blocked) then :blocked
    elsif results.include?(:failed)
      user.update_column(:slack_channels_failed_at, Time.current)
      :failed
    else
      user.update_columns(slack_channels_joined_at: Time.current, slack_channels_failed_at: nil)
      :joined
    end
  end
end
