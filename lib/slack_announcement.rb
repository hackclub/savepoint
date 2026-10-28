# Posts a Block Kit message from a JSON file to a Slack channel as Armand, with his user token (SLACK_USER_TOKEN, scope
# chat:write), so it shows his name and photo and no APP badge. Used by bin/rails "slack:announce[C...,file.json]" and
# only runs when Armand runs it. Never prints or stores the token.
class SlackAnnouncement
  class Refused < StandardError; end

  CHANNEL = /\AC[A-Z0-9]{8,}\z/
  # The wrong tool's old channels. Never posted to.
  REFUSED_CHANNELS = %w[ C0C5UHLAAP5 C0C60KQ0XLJ ].freeze
  TIMESTAMP = /\A\d+\.\d+\z/
  MAX_BLOCKS = 50
  BUILDER_URL = "https://app.slack.com/block-kit-builder/#"

  def self.load(path)
    file = Rails.root.join(path.to_s)
    raise Refused, "give a message file: bin/rails \"slack:announce:preview[announcements/example.json]\"" if path.blank?
    raise Refused, "#{path} does not exist" unless file.file?
    new(file.read)
  end

  # Outside production a real post needs SLACK_LIVE=1, the same switch as the bot (SlackBotToken.live?).
  def self.live!(live: SlackBotToken.live?)
    raise Refused, "Slack sending is off outside production. Run with SLACK_LIVE=1 to post for real." unless live
  end

  # The user token, checked without ever showing it.
  def self.token!(token = ENV["SLACK_USER_TOKEN"])
    raise Refused, "SLACK_USER_TOKEN is empty. Paste the User OAuth Token into .env (see announcements/README.md)." if token.blank?
    raise Refused, "SLACK_USER_TOKEN is set, but that's not a user token (it must start with xoxp-)." unless token.to_s.start_with?("xoxp-")
    token
  end

  def self.check_channel!(channel)
    raise Refused, "give a channel ID: bin/rails \"slack:announce[C0123ABCD,announcements/example.json]\"" if channel.blank?
    raise Refused, "#{channel} is refused. Nothing posts to the wrong tool's channels." if REFUSED_CHANNELS.include?(channel.to_s)
    raise Refused, "#{channel.inspect} is not a channel ID (C followed by capitals and digits)." unless channel.to_s.match?(CHANNEL)
    channel
  end

  def self.check_timestamp!(ts)
    raise Refused, "give the message ts: bin/rails \"slack:announce:update[C0123ABCD,1700000000.000100,announcements/example.json]\"" if ts.blank?
    raise Refused, "#{ts.inspect} is not a message ts (digits, a dot, digits)." unless ts.to_s.match?(TIMESTAMP)
    ts
  end

  attr_reader :blocks, :text

  # `source` is the JSON string: { "text": ..., "blocks": [...] } or a bare blocks array.
  def initialize(source)
    data = begin
      JSON.parse(source.to_s)
    rescue JSON::ParserError => error
      raise Refused, "the message file is not valid JSON: #{error.message.lines.first.to_s.strip}"
    end
    @blocks = data.is_a?(Hash) ? data["blocks"] : data
    @text = data.is_a?(Hash) ? data["text"].to_s.strip : ""
    @text = fallback_text if @text.empty?
    validate!
  end

  def preview_url = BUILDER_URL + ERB::Util.url_encode(JSON.generate(blocks:))

  # Posts to the token owner's own DM so Armand can see the real render. Returns the permalink, or the ts.
  def test!(client: nil)
    client ||= (self.class.live!; Slack::Web::Client.new(token: self.class.token!))
    user_id = client.auth_test.user_id
    post(client, user_id)
  end

  def deliver!(channel, client: nil)
    self.class.check_channel!(channel)
    client ||= (self.class.live!; Slack::Web::Client.new(token: self.class.token!))
    post(client, channel)
  end

  # Replaces the blocks and text of a message the token owner already posted, with chat.update. Returns the permalink, or the ts.
  def update!(channel, ts, client: nil)
    self.class.check_channel!(channel)
    self.class.check_timestamp!(ts)
    client ||= (self.class.live!; Slack::Web::Client.new(token: self.class.token!))
    updated = client.chat_update(channel:, ts:, text:, blocks:)
    permalink(client, updated) || updated.ts
  end

  private
    def post(client, channel)
      sent = client.chat_postMessage(channel:, text:, blocks:, unfurl_links: false, unfurl_media: false)
      permalink(client, sent) || sent.ts
    end

    def permalink(client, sent)
      client.chat_getPermalink(channel: sent.channel, message_ts: sent.ts).permalink
    rescue Slack::Web::Api::Errors::SlackError
      nil
    end

    def validate!
      raise Refused, "blocks must be a non-empty array" unless blocks.is_a?(Array) && blocks.any?
      raise Refused, "at most #{MAX_BLOCKS} blocks, this has #{blocks.size}" if blocks.size > MAX_BLOCKS
      blocks.each_with_index do |block, index|
        raise Refused, "block #{index + 1} needs a \"type\"" unless block.is_a?(Hash) && block["type"].present?
      end
      raise Refused, "no fallback text. Add a \"text\" field, or start with a header or section block that has text." if text.empty?
    end

    # What notifications show: the text of the first header or section block.
    def fallback_text
      return "" unless blocks.is_a?(Array)
      first = blocks.find { |block| block.is_a?(Hash) && %w[ header section ].include?(block["type"]) && block.dig("text", "text").present? }
      first ? first.dig("text", "text").to_s.strip : ""
    end
end
