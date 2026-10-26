# Daily: everyone's Slack display name, so a change on Slack shows up here (see SlackProfileJob).
class SlackProfilesSyncJob < ApplicationJob
  def perform
    User.where.not(slack_id: [ nil, "" ]).find_each { |user| SlackProfileJob.perform_later(user.id) }
  end
end
