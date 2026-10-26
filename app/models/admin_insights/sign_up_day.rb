# Who built on the day they signed up, for the admin home (AdminSummary): for each day, how many participants signed up
# (UTC) and how many of them have a completed streak day (StreakActivity.completed: their first 20 minutes, as Metric's
# first_20 counts it) on that same UTC date. Streak days are kept by date, so "within 24 hours" can only be told as
# "that day". Participants only.
module AdminInsights
  class SignUpDay
    # One row for each of `dates`: { date:, signed_up:, built:, percent: } (percent is nil on a day nobody signed up).
    def self.call(dates:) = new(dates).call

    def initialize(dates)
      @dates = dates
    end

    def call
      return [] if @dates.empty?

      signed_up = people.group("users.created_at::date").count
      built = people.joins(:streak_activities).merge(StreakActivity.completed)
                    .where("streak_activities.activity_date = users.created_at::date").group("users.created_at::date").distinct.count("users.id")
      @dates.map do |date|
        n = signed_up.fetch(date, 0)
        done = built.fetch(date, 0)
        { date:, signed_up: n, built: done, percent: (n.positive? ? (done * 100.0 / n).round : nil) }
      end
    end

    private
      def people = User.participants.where(created_at: @dates.first.beginning_of_day..)
  end
end
