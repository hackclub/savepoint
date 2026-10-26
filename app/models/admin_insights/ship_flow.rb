# Ships and the review wait, for the admin home (AdminSummary): ships created on each day (UTC), and when the oldest ship
# still in review was made, so the page can say how long it has waited. Participants' ships only.
module AdminInsights
  class ShipFlow
    # { days: [ { date:, ships: } for each of `dates` ], in_review: how many, oldest_in_review_at: a Time or nil, awaiting_fraud: how many }
    def self.call(dates:) = new(dates).call

    def initialize(dates)
      @dates = dates
    end

    def call
      per_day = ships.group("ships.created_at::date").count
      waiting = ships.in_review
      { days: @dates.map { |date| { date:, ships: per_day.fetch(date, 0) } }, in_review: waiting.count, oldest_in_review_at: waiting.minimum(:created_at),
        awaiting_fraud: ships.awaiting_fraud.count }
    end

    private
      def ships = Ship.where(project_id: Project.where(user_id: User.participants.select(:id)).select(:id))
  end
end
