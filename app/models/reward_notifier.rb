# Telling people on Slack they've earned a reward (Reward): a DM, and for shoutouts, a post in
# the shoutout channel. Posts are a plain line about them, and go out at the reward's slot (Reward#announce_at), with the DM, so no two shoutouts land together.
module RewardNotifier
  # The DM.
  DMS = {
    "gold_star" => "3-day streak!! You now have a gold star on your sheet :cat-lock-in:",
    "streak_shoutout" => "5-day streak!! You've earned a shoutout in Slack for %{title} :yayayayayay:",
    "stickers" => "Stickers!! You worked on your game in your first hour, so free Hack Club stickers are yours :yayayayayay: Tell us where to send them."
  }.merge(Reward::COMEBACK_STICKER_KEYS.index_with { "Stickers!! You came back and worked on your game, so free Hack Club stickers are yours :yayayayayay: Tell us where to send them." }).freeze

  # The DM's link button, for the ones that point somewhere other than the project page: [label, path].
  LINKS = Reward::STICKER_KEYS.index_with { [ "Claim your stickers", "/shop" ] }.freeze

  # The post in the channel, for the ones that have one.
  POSTS = {
    "streak_shoutout" => "🔥 %{you} has a 5-day streak, building %{title}."
  }.freeze

  def self.posted?(key) = POSTS.key?(key)

  # Each DM is noted as the bot's latest as it's queued (User#slack_dmed!), so a cheer from the same sync waits for
  # it. One held for a slot is noted when it goes (SlackMessageJob).
  def self.earned(reward)
    projects = reward.users.map(&:project)
    messages = reward.announce_at ? SlackMessageJob.set(wait_until: reward.announce_at) : SlackMessageJob
    projects.each do |project|
      next if project.user.slack_id.blank?
      vars = vars_for(project)
      project.user.slack_dmed! unless reward.announce_at
      messages.perform_later(project.user.slack_id, format(DMS.fetch(reward.key), vars), link: link_for(reward.key),
                             gif: "reward.#{reward.key}")
    end

    post(messages, reward, projects.first) if posted?(reward.key)
  end

  # The shoutout, in #savepoint (Program::SHOUTOUT_CHANNEL_ID, D-018). If that is ever blank, it only logs.
  def self.post(messages, reward, project)
    channel = Program::SHOUTOUT_CHANNEL_ID
    text = format(POSTS.fetch(reward.key), vars_for(project))
    if channel.blank?
      Rails.logger.info("Slack (no Save Point channel): would post #{text.inspect}")
    else
      messages.perform_later(channel, text)
    end
  end

  def self.link_for(key)
    label, path = LINKS.fetch(key, [ "Open Save Point", "/project" ])
    [ label, "#{Rails.configuration.x.app_url}#{path}" ]
  end

  # The title is theirs, so it's escaped (SlackText). The mention is built here, so it isn't.
  def self.vars_for(project)
    { you: mention(project), title: "*#{SlackText.escape(project.title)}*" }
  end

  # Their @mention (Slack shows the name they chose there), or what everyone here sees them as if they're not on
  # Slack: never their real name, since a channel is public.
  def self.mention(project)
    user = project.user
    user.slack_id.present? ? "<@#{user.slack_id}>" : SlackText.escape(user.public_name)
  end

  private_class_method :post, :link_for, :vars_for, :mention
end
