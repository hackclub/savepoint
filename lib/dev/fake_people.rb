# Made-up participants for development (bin/rails dev:fake): fake teens with games, hours on every program day (see /dev to pretend it's a given day),
# buddies, ships in each review state and prize orders, so every page has something on it. Safe to run again: each
# person is found by their Hack Club ID ("ident!fake-<slug>") and rewritten, never duplicated. Nothing here touches a
# real user. Their Hackatime hours come from the streak days written here (Hackatime::Fake).
module Dev
  module FakePeople
    PREFIX = "ident!fake-"
    SHOTS = %w[campfire hilltop midnight tables breadboard gadget].freeze
    AVATARS = %w[mia kenji sam].freeze
    ADDRESS = { "street_address" => "1 Example Way", "locality" => "Springfield", "region" => "VT", "postal_code" => "05001", "country" => "US" }.freeze

    # slug, Slack display name, Slack username, game, Hackatime project, prize, timezone, minutes a day on
    # average, how often they build (0 to 1), minutes today, and the ship they're at (nil, :in_review, :approved,
    # :changes_needed)
    PEOPLE = [
      [ "mia", "mia ✨", "mia.codes", "Moth Lantern", "moth-lantern", "steam25", "America/Chicago", 105, 0.95, 80, :approved ],
      [ "kenji", "kenji", "kenji_k", "Rail Rider", "rail-rider", "u2c", "Asia/Tokyo", 95, 0.9, 55, :approved ],
      [ "priya", "priya", "priya.dev", "Tiny Tavern", "tiny-tavern", "micro", "Asia/Kolkata", 85, 0.9, 40, :approved ],
      [ "otto", "otto the otter", "otto", "Otter Dash", "otter-dash", "k617", "Europe/Berlin", 70, 0.85, 25, :in_review ],
      [ "sam", "sam", "sam_makes", "Gravity Garden", "gravity-garden", "aseprite", "America/New_York", 60, 0.8, 0, :in_review ],
      [ "luz", "luz", "luzdev", "Slime Kingdom", "slime-kingdom", "g203", "America/Mexico_City", 55, 0.8, 35, :changes_needed ],
      [ "finn", "finn (he/him)", "finn.b", "Sky Shepherd", "sky-shepherd", "pro2", "Europe/London", 50, 0.75, 0, nil ],
      [ "zara", "zara", "zarazee", "Bubble Bakery", "bubble-bakery", "x3", "America/Los_Angeles", 45, 0.75, 20, nil ],
      [ "dev", "", "dev_codes", "Lava Hop", "lava-hop", "u2", "Asia/Kolkata", 45, 0.7, 30, nil ],
      [ "ines", "", "ines.pixels", "Night Market", "night-market", "k2", "Europe/Lisbon", 40, 0.7, 0, nil ],
      [ "tomasz", "tomasz", "tomek", "Orbit Cleaner", "orbit-cleaner", "u2c", "Europe/Warsaw", 35, 0.65, 15, nil ],
      [ "ava", "ava ♡", "avaa", "Cloud Cats", "cloud-cats", "steam25", "Australia/Sydney", 30, 0.6, 10, nil ],
      [ "rex", "rex", "rex_rawr", "Dino Diner", "dino-diner", "micro", "America/Denver", 28, 0.55, 0, nil ],
      [ "hana", "hana", "hana.hana", "Paper Parade", "paper-parade", "aseprite", "Asia/Seoul", 22, 0.5, 18, nil ],
      [ "nico", "nico", "nico_n", "Crate Escape", "crate-escape", "k617", "America/Sao_Paulo", 18, 0.45, 0, nil ],
      [ "leo", "leo", "leo.lol", "Soup Simulator", "soup-simulator", "g203", "UTC", 14, 0.4, 5, nil ],
      [ "wren", "", "", "Quiet Pond", "quiet-pond", "steam100", "UTC", 10, 0.35, 0, nil ],
      [ "juno", "juno", "juno_j", "Pocket Pirates", "pocket-pirates", "f75", "America/Toronto", 8, 0.3, 0, nil ]
    ].freeze

    # Who's paired (slugs), and who has an invite out already. Everyone else with a game is free to take Armand's invite.
    PAIRS = [ %w[mia kenji], %w[priya otto] ].freeze
    INVITED = %w[dev].freeze
    # Each prize a fake person bought: [ slug, prize key, status ].
    ORDERS = [ %w[mia steam25 waiting], %w[kenji u2c ordered], %w[priya micro waiting] ].freeze

    def self.fake_users = User.where("hca_id LIKE ?", "#{PREFIX}%")

    def self.seed!
      raise "Fake people are for development only." unless Rails.env.development?

      PEOPLE.each { |person| seed_person(*person) }
      Ship.where(decided_by_id: nil, project: Project.where(user: fake_users)).decided.update_all(decided_by_id: reviewer.id)
      PAIRS.each { |slugs| pair!(*slugs) }
      snapshot_ranks!
      ORDERS.each { |slug, prize, status| order!(slug, prize, status) }
      fake_users.count
    end

    def self.reset!
      raise "Fake people are for development only." unless Rails.env.development?

      Ship.where(decided_by: fake_users).update_all(decided_by_id: nil)
      fake_users.destroy_all.size
    end

    # Who decided the made-up ships, so the admin list shows a name and not "someone".
    def self.reviewer
      User.find_or_initialize_by(hca_id: "#{PREFIX}reviewer").tap do |user|
        user.assign_attributes(email: "reviewer@example.com", name: "Orpheus Example", first_name: "Orpheus", verification_status: "verified", ysws_eligible: true)
        user.save!
      end
    end

    def self.seed_person(slug, display, username, game, hackatime, prize, timezone, minutes, consistency, today_minutes, ship)
      random = Random.new(slug.hash.abs % 1_000_000 + slug.sum)
      user = User.find_or_initialize_by(hca_id: "#{PREFIX}#{slug}")
      user.assign_attributes(email: "#{slug}@example.com", name: "#{slug.capitalize} Example", first_name: slug.capitalize,
                             verification_status: "verified", ysws_eligible: true, timezone:, address: ADDRESS,
                             slack_display_name: display.presence, slack_username: username.presence,
                             hackatime_uid: "fake-#{slug}", hackatime_access_token: "fake-token")
      user.slack_avatar_url = avatar_url(slug) if AVATARS.include?(slug) && User.column_names.include?("slack_avatar_url")
      user.save!

      project = user.project || user.build_project
      project.assign_attributes(idea: game.downcase, name: game, prize_key: prize, pace_minutes: Project.pace_for(Prize.find(prize)),
                                build_time: Project::BUILD_TIMES[random.rand(Project::BUILD_TIMES.size)], signed_on: Program::DATES.begin + random.rand(3),
                                hackatime_projects: [ hackatime ], repo_url: "https://github.com/example/#{hackatime}",
                                buddy_code: project.buddy_code.presence || Project.new_buddy_code,
                                buddy_invited: INVITED.include?(slug), jame_gam: slug.sum.odd?)
      project.save!
      attach_screenshot(project, slug)

      days = Program::DATES.to_a
      days.each do |date|
        today = date == Program.today
        seconds = if today then today_minutes * 60
        elsif random.rand < consistency then ((minutes * (0.4 + random.rand * 1.2)).round.clamp(5, 240)) * 60
        else 0
        end
        StreakActivity.find_or_initialize_by(user:, activity_date: date).update!(coded_seconds: seconds)
      end
      user.update_columns(streak_synced_at: Time.current)
      user.recalculate_streak!
      seed_ship(project, ship, slug) if ship
      user
    end

    def self.avatar_url(slug)
      shot = SHOTS[slug.sum % SHOTS.size]
      ActionController::Base.helpers.asset_path("save_point/photos/#{shot}.jpg")
    end

    def self.attach_screenshot(project, slug)
      return if project.screenshot.attached?

      shot = SHOTS[(slug.sum + 2) % SHOTS.size]
      project.screenshot.attach(io: File.open(Rails.root.join("app/assets/images/save_point/photos/#{shot}.jpg")), filename: "#{shot}.jpg", content_type: "image/jpeg")
    end

    def self.seed_ship(project, state, slug)
      return if project.ships.exists?

      hours = project.user.hours_in(Program::FIRST_STREAK_DATE..)
      ship = project.ships.build(title: project.name, description: "#{project.name} is a small game about #{project.idea}. Built in a few evenings, with a lot left to polish.",
                                 repo_url: project.repo_url, demo_url: "https://example.com/play/#{slug}", hackatime_projects: project.hackatime_projects,
                                 hours:, screenshot_shows_game: true)
      shot = SHOTS[(slug.sum + 1) % SHOTS.size]
      ship.screenshot.attach(io: File.open(Rails.root.join("app/assets/images/save_point/photos/#{shot}.jpg")), filename: "#{shot}.jpg", content_type: "image/jpeg")
      ship.save!
      case state
      when :approved then ship.update_columns(status: "approved", fraud_status: "passed", decided_at: 1.day.ago, decided_by_id: reviewer.id, approved_hours: hours, review_hours: hours)
      when :changes_needed then ship.update_columns(status: "changes_needed", decided_at: 2.hours.ago, decided_by_id: reviewer.id, changes_made: nil)
      end
    end

    def self.pair!(first, second)
      one, two = [ first, second ].map { |slug| User.find_by!(hca_id: "#{PREFIX}#{slug}").project }
      return if one.pair

      Pair.create!(first_project: one, second_project: two, started_on: Program::DATES.begin + 1)
    end

    def self.order!(slug, prize, status)
      project = User.find_by!(hca_id: "#{PREFIX}#{slug}").project
      order = project.orders.find_by(prize_key: prize) || project.orders.create!(prize_key: prize)
      order.update_columns(status: "ordered", ordered_at: 1.hour.ago) if status == "ordered"
    end

    # Yesterday's ranks, a little shuffled, so the board shows who has moved.
    def self.snapshot_ranks!
      random = Random.new(7)
      Leaderboard.places(projects: Project.includes(:user)).each do |place|
        next unless place.user.hca_id.start_with?(PREFIX)

        place.project.update_columns(week_rank: [ place.rank + random.rand(-3..3), 1 ].max, week_rank_on: Date.yesterday)
      end
    end
  end
end
