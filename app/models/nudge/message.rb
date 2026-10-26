# A nudge as a Slack message (Block Kit): the text, its GIF if they're on (SlackGifs), then the button and a way to stop these. Both buttons are
# tracked links (see NudgeLinksController).
class Nudge::Message
  attr_reader :nudge

  # `gifs: true` draws the GIF whatever the switch says (SlackDemo); otherwise it's up to SlackGifs.enabled?.
  # `pick` chooses which GIF of the arm's pool (see SlackGifs.block); without it, one at random.
  def initialize(nudge, gifs: false, pick: nil)
    @nudge = nudge
    @gifs = gifs
    @pick = pick
  end

  def blocks
    [
      { type: "section", text: { type: "mrkdwn", text: nudge.text } },
      SlackGifs.block("nudge.#{nudge.arm}", force: @gifs, pick: @pick),
      { type: "actions", elements: [
        { type: "button", text: { type: "plain_text", text: Nudge::Copy.link_for(nudge.arm).first }, style: "primary",
          url: nudge.link_url, action_id: "nudge_open" },
        { type: "button", text: { type: "plain_text", text: Nudge::Copy::SLACK_MUTE }, url: nudge.stop_url, action_id: "nudge_stop" }
      ] }
    ].compact
  end
end
