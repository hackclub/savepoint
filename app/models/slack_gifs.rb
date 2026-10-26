# A pool of GIFs for each participant DM the bot sends, from config/slack_gifs.yml, drawn as a Slack image block. Off unless
# SLACK_GIFS=1 (Rails.configuration.x.slack_gifs), so production sends what it always has. SlackDemo forces them on.
module SlackGifs
  GIFS = YAML.load_file(Rails.root.join("config/slack_gifs.yml"), aliases: true).freeze

  def self.enabled? = Rails.configuration.x.slack_gifs.present?

  # The image block for a key, or nil when GIFs are off (and not forced) or the key has none. A random GIF from the key's
  # pool, or the `pick`th (wrapping round) when given, which is how the demo shows a different one each time.
  def self.block(key, force: false, pick: nil)
    return unless key && (force || enabled?)

    pool = GIFS[key.to_s].presence or return
    gif = pick ? pool[pick % pool.size] : pool.sample
    { type: "image", image_url: gif.fetch("url"), alt_text: gif.fetch("alt") }
  end
end
