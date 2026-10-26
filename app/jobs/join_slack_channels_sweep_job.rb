# Every 10 minutes: adds a small batch of people whose Slack is linked but who aren't in the channel yet (D-028). This
# covers everyone who signed in before the channel was set, and anyone whose sign-in invite failed. Stops at the first
# sign that Slack or the bot is the problem (the bot not being in the channel, rate limits), logging once, and tries
# again next run.
class JoinSlackChannelsSweepJob < ApplicationJob
  BATCH = 20

  def perform
    return if Program::SLACK_CHANNEL_IDS.empty?

    User.where(slack_channels_joined_at: nil, slack_channels_failed_at: nil).where.not(slack_id: [ nil, "" ])
        .order(:id).limit(BATCH).pluck(:id).each do |user_id|
      if JoinSlackChannelsJob.perform_now(user_id) == :blocked
        Rails.logger.warn("Slack channel sweep stopped: Slack refused the invite for a reason that isn't about the person (see the line above). Trying again next run.")
        break
      end
    rescue Slack::Web::Api::Errors::TooManyRequestsError
      Rails.logger.warn("Slack channel sweep stopped: rate limited. Trying again next run.")
      break
    end
  end
end
