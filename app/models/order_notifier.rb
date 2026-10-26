# Telling people on Slack about a claimed prize (Order): the admins when someone claims (what, and a button to the
# queue), and a DM to them once it's ordered.
module OrderNotifier
  # To each admin. Their real name's fine here: it's a DM to an admin, not a channel.
  ADMIN_DM = "%{name} claimed the %{configuration} with %{hours} approved %{hours_word}. Order it, then mark it ordered."
  # The free ones (the D-051 stickers) cost no hours, so saying "0 approved hours" would only confuse.
  ADMIN_DM_FREE = "%{name} claimed their free %{configuration}. Order them, then mark them ordered."

  DM = "Your %{configuration} is ordered, yay!! :yayayayayay:"
  # The free stickers (D-067) are sent by Hack Club, so they never say "ordered".
  DM_STICKERS = "Your stickers are on their way! :yayayayayay:"

  def self.claimed(order)
    user = order.project.user
    hours = order.hours.to_f.round(1).to_s.delete_suffix(".0")
    hours_word = hours == "1" ? "hour" : "hours"
    name = SlackText.escape(user.name.presence || user.public_name)
    text = if order.hours.to_f.zero?
      format(ADMIN_DM_FREE, name:, configuration: order.configuration)
    else
      format(ADMIN_DM, name:, configuration: order.configuration, hours:, hours_word:)
    end
    Rails.configuration.x.admin_slack_ids.each do |slack_id|
      SlackMessageJob.perform_later(slack_id, text, link: [ "Open the queue", "#{Rails.configuration.x.app_url}/admin/orders" ])
    end
  end

  # Noted as the bot's latest DM as it's queued (User#slack_dmed!). Nothing if they're not on Slack or stopped its
  # messages.
  def self.ordered(order)
    user = order.project.user
    return if user.slack_id.blank? || user.slack_muted_at.present?

    user.slack_dmed!
    text = order.try(:stickers?) ? DM_STICKERS : format(DM, configuration: order.configuration)
    SlackMessageJob.perform_later(user.slack_id, text, link: [ "Open the shop", "#{Rails.configuration.x.app_url}/shop" ], gif: "order.ordered")
  end
end
