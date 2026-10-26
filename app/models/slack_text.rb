# Text that someone else wrote, made safe to put in a Slack message. Slack reads <, > and & in mrkdwn: <!channel>
# pings everyone, and <https://x|label> shows a link under any label. Escape each of them, as Slack documents
# (https://api.slack.com/reference/surfaces/formatting#escaping), before a title, a name or a reason goes into a message.
# Do not escape what the code builds itself, such as a <@U…> mention or a link. * and _ stay, so bold and italics work.
# Control characters go too, except the newline.
module SlackText
  CONTROL = /[[:cntrl:]&&[^\n]]/
  ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }.freeze

  def self.escape(text)
    text.to_s.gsub(CONTROL, "").gsub(/[&<>]/, ESCAPES)
  end
end
