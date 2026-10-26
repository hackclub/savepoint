# Who can see the admin pages (like /admin/nudges), and who gets the admin DMs: anyone whose Slack ID is in
# ENV["ADMIN_SLACK_IDS"] (comma or whitespace separated; an Orchard env var in production, where there are
# no credentials) or in admin_slack_ids in Rails credentials. Both lists are merged. In development, anyone signed in.
require Rails.root.join("lib/admin_slack_ids")

Rails.application.config.x.admin_slack_ids = AdminSlackIds.resolve
