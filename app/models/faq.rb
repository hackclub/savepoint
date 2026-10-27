# The landing page's FAQ (D-093, D-094): groups of questions, each group with a fixed anchor and each question with a stable
# key. The key is the group's anchor and a slug of the question, so adding or moving a question never changes another's link.
# The page renders from Faq.groups(view), and FaqRead accepts only the keys listed here.
class Faq
  Group = Data.define(:slug, :title, :entries)
  Entry = Data.define(:key, :question, :answer)

  KEY_LENGTH = 60

  class << self
    # [Group, ...] in page order. `view` is a view context (or ApplicationController.helpers) for the dates and links in answers.
    def groups(view = ApplicationController.helpers)
      start, finish = view.short_date(Program::STARTS_AT), view.short_date(Program::ENDS_AT)
      link = ->(text, url) { view.link_to(text, url) }
      raw = [
        [ "basics", "The basics", [
          [ "Does my game need to be from a game jam?", "No. You can continue any game that you deem as incomplete." ],
          [ "Can I start a new game?", "If you're re-imagining a game that you've made in the past, sure. But if it's something brand new, no." ],
          [ "What is Save Point?", "A Hack Club program for finishing games. Pick a game you started and didn't finish, work on it from #{start} to #{finish}, track your time with Hackatime, and ship it. Every approved hour counts toward a prize you choose." ],
          [ "Who can join?", "Anyone aged 13 to 18, anywhere in the world. You need a Hack Club account, and it has to be verified before we can send you a prize." ],
          [ "Is this legit?", "Yes. Save Point is run by Hack Club, a 501(c)(3) nonprofit, and paid for by its donors. It costs you nothing." ],
          [ "Which games count?", "Any game you started and haven't finished: a game you dropped last year, or one you're still polishing. Use any engine or language, as long as Hackatime can track your time in it." ],
          [ "Is it too late to join?", "Not until #{finish}. The hours you spend on your game from #{start} count, even if you sign up later." ]
        ] ],
        [ "hours", "Hours", [
          [ "What counts as an hour?", "Time Hackatime records on your game between #{start} and #{finish}. A reviewer checks the hours when you ship." ],
          [ "Do I need Hackatime?", view.safe_join([ "Yes. It's how we count your hours. ", link.("Set it up", "https://hackatime.hackclub.com/"), " before you start, because time it didn't record can't count." ]) ],
          [ "Does art time count?", view.safe_join([ "Yes. Track your art with ", link.("Lapse", "https://lapse.hackclub.com"), ". Art counts for up to 30% of your approved hours. So 7 hours of code allows 3 hours of art. If you log 7 hours of code and 5 hours of art, only 3 hours of art count." ]) ],
          [ "What if Hackatime can't track my editor?", view.safe_join([ "For an editor like GameMaker Studio, track your time with ", link.("Lapse", "https://lapse.hackclub.com"), " instead. The reviewer decides how much of that time was coding. Only the art part counts toward the 30% art limit. You don't need to flag anything when you ship." ]) ],
          [ "I worked on this game before Save Point. Does that count?", "No. Only new time counts, from #{start} on." ],
          [ "I shipped this game to another Hack Club program. Can I bring it?", "Yes. Hours another program already counted can't count again, but new time can." ]
        ] ],
        [ "how-to-ship", "Shipping your game", [
          [ "What do I need to ship?", "A link to your code, a playable build (itch.io is fine), a screenshot, and a short note on what you changed. The ship checker tells you what's still missing before you send it." ],
          [ "How do you check what I changed?", "A reviewer reads your note next to the commits you made during Save Point, and compares your screenshot with your game's last ship to Hack Club, if it has one." ],
          [ "What if my ship needs changes?", "You'll get a note saying what to fix. Fix it and send it again. You don't lose any hours." ]
        ] ],
        [ "shipping", "What counts as a shipped project?", [
          [ "What does my repository need?", "It has to be public and have a README that says what the game is and how to run it. The README also has to contain your playable link. The ship checker flags each one that's missing." ],
          [ "What does the playable link need?", "It has to load for someone who isn't signed in, and the game has to run from it. The reviewer opens it and plays." ],
          [ "What does my screenshot need?", "A new still image (PNG, JPEG or WebP, under 5 MB, not a GIF) that shows your game running. You can't reuse one from an earlier ship." ],
          [ "Does my game have to change during Save Point?", "Yes. Make commits from #{start} on and say in your note what you changed. The reviewer compares them, and your screenshot, with the game's last ship. A game with no new work doesn't pass." ],
          [ "Can I use AI?", "Your game can't be made by AI, and AI art isn't allowed, so make your own assets. If AI helped write some of the code, that time counts for a third of its length. Art counts up to 30% of your approved hours, as above." ],
          [ "What else does the reviewer check?", "That the game runs, that the README says how to run it, that your hours fit the size of what you changed, and that those hours weren't already approved in another Hack Club program." ],
          [ "What's the difference between changes needed and rejected?", "Changes needed means the ship falls short. You get a note, you fix it, and you ship again with your hours kept. Rejected is final for that ship, and the reviewer writes why." ]
        ] ],
        [ "prizes", "Prizes", [
          [ "How do prizes work?", "Each approved hour adds to your balance. Pick a prize as your goal and the site shows how many hours a day get you there by #{finish}. When you have enough hours, claim it." ],
          [ "Can I get more than one prize?", "Yes, if you have the hours. Each prize costs its hours, and you can claim each one once." ],
          [ "Do you ship to my country?", "We ship worldwide, and each prize's budget includes shipping to places like India. Some items have batteries that couriers won't take everywhere. If yours can't reach you, we'll work out a swap with you." ],
          [ "What if my prize isn't available where I live?", "If a prize is unavailable, for example because of restrictions in your region, we may contact you to find another prize that is available." ],
          [ "How do Steam gift cards work?", "Steam sends a gift card to your account from a Steam friend, so you add us on Steam. Steam makes new friends wait 3 days before they can send one, so add us early." ]
        ] ],
        [ "help", "Help", [
          [ "Where do I ask questions?", view.safe_join([ "In the ", link.("Hack Club Slack", "https://hackclub.com/slack/"), ". Armand runs Save Point and reads everything." ]) ]
        ] ]
      ]
      raw.map do |slug, title, questions|
        Group.new(slug:, title:, entries: questions.map { |question, answer| Entry.new(key: key_for(slug, question), question:, answer:) })
      end
    end

    # "shipping.what-does-my-repository-need": the group's anchor, a dot, then the question as a slug.
    def key_for(slug, question) = "#{slug}.#{question.parameterize.first(KEY_LENGTH).chomp("-")}"

    # Every key on the page, for FaqRead to check against.
    def keys = groups.flat_map { |group| group.entries.map(&:key) }

    # Key => the question's text.
    def questions = groups.flat_map(&:entries).to_h { [ it.key, it.question ] }
  end
end
