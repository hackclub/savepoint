module ApplicationHelper
  # The landing page's description: the meta description of every page that sets no content_for(:description) of its own,
  # and the link preview's text (layouts/_social_tags).
  def site_description
    "Finish the game you started. Work on an unfinished game from #{short_date(Program::STARTS_AT)} to #{short_date(Program::ENDS_AT)}, track your hours, and earn a controller, keyboard, mouse or Steam credit. A Hack Club program for teenagers."
  end

  # Someone's picture: their Slack one, or else the first letter of what everyone sees them as (never their real
  # name) on their colour, drawn by CSS so it never lands in copied or read text. The wrapper carries the name for screen readers and on hover.
  def avatar_tag(user, class_name = nil, **options)
    name = user.public_name
    attributes = { class: [ "avatar", class_name ], style: "--avatar-color: #{user.avatar_color}", role: "img",
                   aria: { label: name }, title: name }
    tag.span(**attributes.merge(options)) do
      if user.slack_avatar_url.present?
        image_tag(user.slack_avatar_url, alt: "", loading: "lazy", referrerpolicy: "no-referrer", class: "avatar__image")
      else
        tag.span(class: "avatar__initial", data: { initial: name.first.upcase }, aria: { hidden: true })
      end
    end
  end

  # The name an admin sees someone by: their Hack Club name, else what everyone sees them as.
  def admin_person_name(user) = user.name.presence || user.public_name

  # Their name as a link to their page in the admin (Admin::UsersController#show). Admin pages only.
  def admin_person_link(user, **options)
    link_to admin_person_name(user), admin_user_path(user), **options, class: [ "admin-person", options[:class] ]
  end

  # Their picture as a link to the same page. The name beside it is the link a keyboard or screen reader uses, so this one
  # is skipped by both, and takes no space of its own.
  def admin_avatar_link(user, class_name = nil, **options)
    link_to admin_user_path(user), class: "admin-person-avatar", tabindex: -1, aria: { hidden: true } do
      avatar_tag(user, class_name, aria: { hidden: true }, role: nil, title: nil, **options)
    end
  end

  SLACK_PROFILE_URL = "https://hackclub.slack.com/team/%<id>s".freeze

  # What everyone sees someone as (User#public_name), and, when they've linked their Slack, the whole name as one link
  # to their Slack profile in a new tab, with a small external-link icon after it as the cue. The last word and the icon
  # share a no-wrap span, so the icon never lands alone on a line. With no Slack, it's just the name. Pass name: for
  # other text, such as "You + Sam" when only the last part is theirs; extra options go on the link.
  def name_with_slack(user, name: user.public_name, **options)
    return name if user.slack_id.blank?

    head, last = name.to_s.then { |text| text.include?(" ") ? text.rpartition(" ").values_at(0, 2) : [ nil, text ] }
    link_to format(SLACK_PROFILE_URL, id: user.slack_id),
            **{ class: [ "slack-name", options.delete(:class) ], target: "_blank", rel: "noopener noreferrer",
                aria: { label: "#{name}'s Slack profile (opens in a new tab)" } }.merge(options) do
      safe_join([ (head ? "#{head} " : nil), tag.span(safe_join([ last, sp_icon("external-link-fill", "slack-name__icon") ]), class: "slack-name__end") ].compact)
    end
  end
end
