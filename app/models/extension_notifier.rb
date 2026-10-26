# Telling people on Slack about an extension (Extension): the admins when someone asks (why, and a button to decide),
# and a DM to them once it's decided.
module ExtensionNotifier
  # To each admin. Their real name's fine here: it's a DM to an admin, not a channel.
  ADMIN_DM = "%{name} asked for #{Program::EXTENSION_DAYS} more days on *%{title}*:\n>%{reason}"

  DMS = {
    "approved" => "#{Program::EXTENSION_DAYS} more days! *%{title}* is due %{deadline} now. Ship it whenever it's playable :)",
    "denied" => "No extra days this time, so *%{title}* is still due %{deadline}. Whatever it is by then, ship it, i'd love to see it :)"
  }.freeze

  def self.requested(extension)
    project = extension.project
    user = project.user
    # All of it is theirs, so it's escaped (SlackText). The reason is quoted, so it's squeezed to one line: a newline would end the quote.
    text = format(ADMIN_DM, name: SlackText.escape(user.name.presence || user.public_name), title: SlackText.escape(project.title),
                  reason: SlackText.escape(extension.reason).squish)
    Rails.configuration.x.admin_slack_ids.each do |slack_id|
      SlackMessageJob.perform_later(slack_id, text, link: [ "Decide on Save Point", "#{Rails.configuration.x.app_url}/admin/extensions" ])
    end
  end

  # Noted as the bot's latest DM as it's queued (User#slack_dmed!), like Project#dm_about_auto_link, so a nudge in the
  # same hour holds off. Nothing if they're not on Slack or stopped its messages.
  def self.decided(extension)
    project = extension.project.reload # so its deadline sees the decision
    user = project.user
    return if user.slack_id.blank? || user.slack_muted_at.present?

    user.slack_dmed!
    text = format(DMS.fetch(extension.status), title: SlackText.escape(project.title), deadline: project.deadline.strftime("%b %-d"))
    SlackMessageJob.perform_later(user.slack_id, text, link: [ "Open Save Point", "#{Rails.configuration.x.app_url}/project" ],
                                  gif: "extension.#{extension.status}")
  end
end
