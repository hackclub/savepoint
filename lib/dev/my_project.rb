# What /dev does to your own project so you can walk through the goal and the shop: set your logged hours (through the
# fake Hackatime, Hackatime::Fake) and your approved hours (a made-up approved ship), forget your orders, and show the
# "you've earned it" popup again. Reached only from Dev::FakesController, whose routes exist in development alone.
module Dev
  class MyProject
    # The levels the presets offer, as a percent of your goal prize's hours.
    PERCENTS = [ 0, 25, 50, 75, 99, 100, 130 ].freeze
    SHIP_TITLE = "Dev approved ship".freeze

    def initialize(project)
      @project = project
    end

    # The hours a preset means: a percent of the goal's hours, rounded down to a tenth so 99% never rounds up to the whole.
    def self.hours_at(goal_hours, percent)
      (goal_hours.to_r * percent / 100).floor(1)
    end

    def hours_at(percent) = self.class.hours_at(@project.hours_needed, percent)

    # Your logged hours become exactly `hours` (Project#hours_logged), or with nil the usual made-up pattern.
    def set_logged!(hours)
      raise "Fake Hackatime is off." unless Hackatime.fake

      user = @project.user
      Hackatime::Fake.pin_hours!(user, hours)
      user.streak_activities.where(activity_date: Program::FIRST_STREAK_DATE..).delete_all
      if hours
        Hackatime::Fake.pinned_days(hours.to_r).each { |date, seconds| user.streak_activities.create!(activity_date: date, coded_seconds: seconds) }
        user.update_column(:streak_synced_at, Time.current)
        user.recalculate_streak!
      else
        user.update_column(:streak_synced_at, nil)
      end
      @project.instance_variable_set(:@hours_logged, nil)
    end

    # What you can spend (Project#hours_to_spend) becomes `hours`: a made-up approved ship holds those hours plus what you've
    # spent already. An approved ship of your own with more hours would win over it, so the answer says so.
    def set_approved!(hours)
      ship = @project.ships.find_by(title: SHIP_TITLE)
      total = (hours + @project.hours_spent).to_d
      return ship&.destroy if hours.zero? && @project.hours_spent.zero?

      ship ||= @project.ships.build(title: SHIP_TITLE, description: "Made by /dev, in development only, so there is something approved to spend.",
                                    repo_url: "https://github.com/example/dev", demo_url: "https://example.com/dev", screenshot_shows_game: true)
      ship.hours = total
      ship.screenshot.attach(io: File.open(Rails.root.join("app/assets/images/save_point/photos/campfire.jpg")), filename: "campfire.jpg", content_type: "image/jpeg") unless ship.screenshot.attached?
      ship.save!
      ship.update_columns(status: "approved", fraud_status: "passed", decided_at: Time.current, approved_hours: total, review_hours: total)
      @project.ships.reset
      @project.hours_to_spend
    end

    def reset_orders!
      @project.orders.destroy_all
    end

    def reset_goal_popup!
      @project.update_column(:goal_reached_seen_key, nil)
    end
  end
end
