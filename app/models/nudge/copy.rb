# Everything a nudge says: a message that is plain and short (what's true and one easy next step, never guilt).
# It's written in lowercase. Each arm has a few variants of about the same intensity, so the bandit learns which
# framing works rather than which sentence; we rotate through them so nobody gets the same one twice in a row.
#
# %{...} fills in from Nudge::Context#vars. A variant whose values aren't there (no streak yet, too few peers) isn't
# picked.
module Nudge::Copy
  # Bandit arms.
  ARMS = {
    # How close you are to your prize: the hours it takes (Shop), never the money.
    "progress" => [
      "%{hours} of %{hours_needed} hours on %{title} so far! about %{sessions_left} more %{pace}-minute %{sessions_word} to %{a_prize} :)",
      "you're %{percent}%% of the way to %{a_prize}, yay!",
      "%{hours_left} %{hours_left_word} left! at %{pace} minutes a session you'd finish by %{finish_on} :)",
      "one %{pace}-minute session gets you %{session_percent}%% closer to %{a_prize}!"
    ],
    # Keep it going. Only for people with a streak.
    "streak" => [
      ":cat-lock-in: %{streak} %{streak_word} in a row on %{title}!! today makes it %{streak_next}",
      "you've built %{streak} %{streak_word} in a row, that's so cool! 20 minutes today keeps it going :)",
      ":cat-lock-in: %{streak} %{streak_word}! %{days_to_reward} more %{reward_days_word} and you unlock %{next_reward}",
      "20 minutes today keeps your streak going :cat-lock-in:"
    ],
    # What you told us at the pledge, in your words and at your time.
    "pledge" => [
      "it's %{local_time}! you said %{build_time}, %{pace} minutes on %{title} :)",
      "this is the time you picked for %{title}, no pressure :)",
      "you pledged %{pace} minutes a session, so here's your reminder!",
      "it's %{build_time}! %{title} is ready when you are :)"
    ],
    # Make starting easy.
    "tiny_step" => [
      "no need to finish anything today! open %{title}, fix one thing, close it. that counts :)",
      "20 minutes, one small feature. that's enough for today!",
      "one small task: make one thing in %{title} a little less broken :)",
      "you don't have to feel like it, just open %{title}. it usually gets easier after a few minutes :)"
    ],
    # Other people are building.
    "social" => [
      "%{peers} people logged time today!",
      "%{peers} people made something new today, maybe you're next? :)",
      "people are building games today! %{title} could be next :)",
      "it's busy today, come build %{title} with us :shaking-rock:"
    ],
    # The leaderboard: who's just above you and how little it takes to pass them. Only when you have hours this
    # week and they're within a session (Nudge::Context#leaderboard_vars). The last one's for when they went past
    # you since yesterday.
    "overtake" => [
      "%{above} is %{gap_minutes} %{gap_word} ahead of you on the leaderboard. one session passes them!",
      "you're #%{rank} this week! %{gap_minutes} %{gap_word} puts you past %{above} :)",
      "only %{gap_minutes} %{gap_word} between you and %{above}, that's less than one session!",
      "%{passed_by} passed you since yesterday, but %{gap_minutes} %{gap_word} takes the spot back :)"
    ],

    # Cheers, sent right after the day's 20 minutes (Nudge::Cheer). %{day} is "today" or "yesterday", and
    # %{next_day} "tomorrow" or "today", so a cheer held for the morning still reads right.
    # Just that they did it.
    "cheer_done" => [
      "%{minutes} minutes on %{title} %{day}, yay!! that's a build day :yay:",
      "you built %{day}! %{minutes} minutes, logged and counted :)",
      "%{day} counts! %{minutes} minutes on %{title} :)",
      "%{minutes} minutes %{day}. that's not nothing, that's a lot actually!"
    ],
    # What it added up to.
    "cheer_progress" => [
      "%{minutes} minutes %{day}! that's %{hours} of %{hours_needed} hours, %{hours_left} %{hours_left_word} to %{a_prize} :)",
      "%{day}'s %{minutes} minutes put you at %{percent}%% of %{a_prize}, yay!",
      "%{hours} %{hours_word} on %{title} so far! %{sessions_left} more %{sessions_word} at your pace and it's %{a_prize} :)"
    ],
    # The streak it kept going. Only for people with one.
    "cheer_streak" => [
      ":cat-lock-in: %{streak} %{streak_word} in a row on %{title}!! %{next_day} makes it %{streak_next}",
      "that's %{streak} %{streak_word} running, so cool! %{days_to_reward} more %{reward_days_word} and you unlock %{next_reward} :)",
      ":cat-lock-in: %{streak}! %{minutes} minutes %{day} kept it going"
    ],
    # The next one.
    "cheer_tomorrow" => [
      "%{minutes} minutes %{day}! same again %{next_day}? %{build_time}, %{pace} minutes :)",
      "you built %{day}! the hard part of %{next_day} is done already, you know it works :)",
      "%{day}: done! %{next_day}: %{build_time} :)"
    ],
    # Who else did.
    "cheer_social" => [
      "%{peers} people built %{day}, and you're one of them!",
      "you and %{peers} others logged time %{day} :)"
    ]
  }.freeze

  # Nudges that always send when they apply (see Nudge::Fixed).
  FIXED = {
    # Setup, one missing step at a time.
    "hackatime" => [ "your hours start counting once hackatime is linked, it only takes about 2 minutes :)" ],
    "plugin" => [ "nothing from you has reached hackatime yet! turn the hackatime plugin on in your editor and write a line: %{title} links itself :)" ],
    "hackatime_project" => [ "hackatime has time from you, but %{title} isn't linked to any of it yet. pick your project and your hours count :)" ],
    "repo" => [ "add your repo link to %{title} so it counts when you ship :)" ],
    # For people who signed in but have no project (Nudge.deliver_pledge_nudges), so nothing about a project here.
    "pledge_setup" => [ "you signed in but haven't picked a game yet! pledge the game you'll continue and your hours start counting :)" ],

    # Milestones (Nudge::Fixed.milestones): halfway to your pick's price, and there.
    "first_session" => [ "first session logged!! %{title} exists now :yay:" ],
    "halfway" => [ "%{hours} %{hours_word}, halfway to %{a_prize}!! :cat-lock-in:" ],
    "done" => [ "%{hours_needed} hours! you've earned %{a_prize}, go claim it :yayayayayay:" ],

    # Program dates. "_done" is for people whose hours already cover their pick.
    "kickoff" => [ "Save Point starts today! :shaking-rock: %{title}, %{build_time}, %{pace} minutes." ],
    "three_days_left" => [ "3 days left! %{hours_left} more %{hours_left_word} and %{a_prize} is yours :)" ],
    "three_days_left_done" => [ "3 days left, and you've already won! anything you build now is a bonus :)" ],
    "last_day" => [ "last day of Save Point! whatever %{title} is right now, ship it :)" ],
    "last_day_done" => [ "last day of Save Point! you earned %{a_prize} building %{title} :yay:" ],

    # Before a streak ends.
    "streak_saver" => [ "your %{streak}-day streak ends at midnight! 20 minutes saves it :cat-lock-in:" ],

    # After a missed day (Nudge::Fixed.comeback), to someone who has built before. The first promises a free sticker pack for
    # coding %{sticker_minutes} minutes in the next 24 hours, so it only goes to someone who can have one; the second doesn't.
    "comeback_stickers" => [
      "we missed you yesterday! code %{sticker_minutes} minutes on %{title} in the next 24 hours and a free sticker pack is yours :yayayayayay:",
      "come back to %{title} for %{sticker_minutes} minutes in the next 24 hours and we'll send you free hack club stickers :)",
      "%{title} misses you! %{sticker_minutes} minutes on it in the next 24 hours gets you a free sticker pack :yay:"
    ],
    "comeback" => [
      "we missed you yesterday! %{title} is ready when you are, even a few minutes counts :)",
      "hey, %{title} misses you! come back for a few minutes today, no pressure :)",
      "you've built %{title} before and it's waiting for you! one small fix today? :cat-lock-in:"
    ]
  }.freeze

  # Where each nudge's one button goes.
  LINKS = {
    "progress" => [ "see your progress", :project ],
    "streak" => [ "keep it going", :project ],
    "pledge" => [ "open your project", :project ],
    "tiny_step" => [ "start 20 minutes", :project ],
    "social" => [ "open your project", :project ],
    "overtake" => [ "see the leaderboard", :leaderboard ],
    "cheer_done" => [ "see your progress", :project ],
    "cheer_progress" => [ "see your progress", :project ],
    "cheer_streak" => [ "see your streak", :project ],
    "cheer_tomorrow" => [ "open your project", :project ],
    "cheer_social" => [ "see your progress", :project ],
    "hackatime" => [ "link hackatime", :hackatime ],
    "plugin" => [ "set up the plugin", :hackatime_site ],
    "hackatime_project" => [ "pick your project", :project ],
    "repo" => [ "add your repo", :project ],
    "pledge_setup" => [ "pledge your game", :onboarding ],
    "first_session" => [ "see your progress", :project ],
    "halfway" => [ "see your progress", :project ],
    "done" => [ "claim your prize", :project ],
    "kickoff" => [ "open your project", :project ],
    "three_days_left" => [ "open your project", :project ],
    "three_days_left_done" => [ "see your progress", :project ],
    "last_day" => [ "ship it", :project ],
    "last_day_done" => [ "see your progress", :project ],
    "streak_saver" => [ "save your streak", :project ],
    "comeback_stickers" => [ "come back for stickers", :project ],
    "comeback" => [ "open your project", :project ]
  }.freeze

  SLACK_MUTE = "stop these messages"

  def self.variants_for(arm)
    ARMS[arm] || FIXED.fetch(arm)
  end

  # Variants with everything they need. If none fit, the arm can't be sent right now.
  def self.renderable(arm, vars)
    variants_for(arm).each_with_index.select { |text, _| (keys(text) - vars.keys).empty? }
  end

  def self.renderable?(arm, vars)
    renderable(arm, vars).any?
  end

  # Returns [variant, text]: the next variant this person hasn't just had.
  def self.render(nudge, vars)
    options = renderable(nudge.arm, vars)
    last = nudge.user.nudges.where(arm: nudge.arm).order(:sent_at).last&.variant
    text, variant = options.reject { |_, index| index == last }.sample || options.sample
    [ variant, format(text, **vars) ]
  end

  def self.link_for(arm)
    LINKS.fetch(arm)
  end

  def self.keys(text)
    text.scan(/%\{(\w+)\}/).flatten.map(&:to_sym)
  end
end
