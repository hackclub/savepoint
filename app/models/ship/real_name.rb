# D-143: the app's guess at whether a participant's first and last name are a real person's name. It only finds reasons to doubt.
# It never says "real": checklist_defaults returns unticked either way, and a reviewer or an agent ticks the item.
class Ship::RealName
  KEYBOARD_RUNS = %w[qwer wert erty rtyu tyui yuio uiop asdf sdfg dfgh fghj ghjk hjkl zxcv xcvb cvbn vbnm qazw wsxe 1234].freeze
  NAME_CHARS = /\A[\p{L}\p{M}][\p{L}\p{M} '.’-]*\z/

  def initialize(ship)
    @ship = ship
    @user = ship.project.user
  end

  # The first and last name as the Unified YSWS row will carry them.
  def names = AirtableFields.names(@user)

  # The first reason to doubt the name, or nil when none of the checks fire.
  def concern
    first, last = names
    return "No HCA first name yet, they need to sign in again. This cannot pass." if first.blank?
    return "No HCA last name yet, they need to sign in again. This cannot pass." if last.blank?
    return "The last name is one character." if last.length < 2
    return "The first name is one character." if first.length < 2
    return "The first and last name are the same word." if squash(first) == squash(last)
    return "The name has digits or symbols." unless first.match?(NAME_CHARS) && last.match?(NAME_CHARS)
    return "The name matches the participant's Slack name or GitHub username, so it may be a handle." if handle?(first, last)
    return "The name looks like keyboard mash." if mash?(first) || mash?(last)

    nil
  end

  private
    def squash(text) = text.to_s.downcase.gsub(/[^\p{L}\p{N}]/, "")

    def handles
      [ @user.slack_display_name, @user.slack_username, github_username ].map { squash(it) }.compact_blank
    end

    def github_username = @ship.repo_url.to_s[%r{\Ahttps://github\.com/([\w-]+)/}, 1]

    def handle?(first, last)
      candidates = [ squash(last), squash(first + last), squash(last + first) ]
      handles.any? { |handle| candidates.include?(handle) }
    end

    # No vowel in a word of four letters or more, a run of one letter, or a run of keys side by side.
    def mash?(word)
      text = squash(word)
      return true if text.length >= 4 && !text.match?(/[aeiouy]/)
      return true if text.match?(/(.)\1{2,}/)

      KEYBOARD_RUNS.any? { text.include?(it) }
    end
end
