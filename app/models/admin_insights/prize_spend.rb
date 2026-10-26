# What prizes cost, for the admin home (AdminSummary): the dollars of prizes participants have claimed already (the cost of
# each Order's prize, Prize#cost), split by whether it's waiting to be ordered or ordered, and a projection: the cost of
# the goal of everyone who has reached it or is on track for it (AdminInsights::GoalPace) and hasn't claimed it. Free stickers cost 0.
module AdminInsights
  class PrizeSpend
    def self.call(pace) = new(pace).call

    def initialize(pace)
      @pace = pace
    end

    # { waiting: { count:, dollars: }, ordered: { count:, dollars: }, claimed_dollars:, projected: { count:, dollars: } }
    def call
      spent = Order::STATUSES.index_with { |status| { count: 0, dollars: 0.0 } }
      orders.each do |status, prize_key|
        spent[status][:count] += 1
        spent[status][:dollars] += Prize.find(prize_key)&.cost.to_f
      end
      likely = @pace.fetch(:goals).select { |goal| %i[reached on_track].include?(goal[:status]) }
      spent.transform_values { |row| row.merge(dollars: row[:dollars].round(2)) }.symbolize_keys.merge(
        claimed_dollars: spent.values.sum { |row| row[:dollars] }.round(2),
        projected: { count: likely.size, dollars: likely.sum { |goal| goal[:cost].to_f }.round(2) }
      )
    end

    private
      def orders = Order.where(project_id: Project.where(user_id: User.participants.select(:id)).select(:id)).pluck(:status, :prize_key)
  end
end
