# Who the admins are: Slack IDs from ENV["ADMIN_SLACK_IDS"] (comma or whitespace separated) merged with
# Rails credentials admin_slack_ids.
module AdminSlackIds
  def self.resolve(env: ENV, credentials: Rails.application.credentials)
    from_env = env["ADMIN_SLACK_IDS"].to_s.split(/[\s,]+/)
    (from_env + Array(credentials.admin_slack_ids).map(&:to_s)).compact_blank.uniq
  end
end
