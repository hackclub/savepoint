# Who is on track for the prize they're aiming for, for the admin home (AdminSummary). Participants with a project and a
# chosen goal, each as reached, on track or behind, against the pace each pledged (Project#pace_minutes).
#
# The definition. What someone needs now is Project#hours_to_go over Project#days_left (their own build days, today
# included), in minutes a day, rounded up to the next 5 the way Prize.pace_minutes rounds. They are:
#   reached   they've the hours already (hours_to_go is 0);
#   on track  they need no more a day now than the pace they pledged (needed <= project.pace_minutes);
#   behind    they need more a day now than they pledged, or have hours to go and no build days left.
# With no pledge, it's the goal's own pace from when their hours start (Project#hours_start, D-065), not from the launch.
# Someone who has claimed their goal (Project#goal_claimed?) is counted apart: it's in the prize spend already.
module AdminInsights
  class GoalPace
    STATUSES = %i[reached on_track behind].freeze

    def self.call = new.call

    # { reached:, on_track:, behind:, claimed:, goals: [ { status:, prize_key:, cost: } ] } where goals are the unclaimed ones.
    def call
      goals = []
      claimed = 0
      projects.each do |project|
        goal = project.chosen_prize or next
        if project.goal_claimed?
          claimed += 1
        else
          goals << { status: status(project, goal), prize_key: goal.key, cost: goal.cost }
        end
      end
      { **STATUSES.index_with { |status| goals.count { |goal| goal[:status] == status } }, claimed:, goals: }
    end

    private
      def projects = Project.where(user_id: User.participants.select(:id)).where.not(prize_key: nil).includes(:user, :orders)

      def status(project, goal)
        to_go = project.hours_to_go
        return :reached if to_go.zero?

        days = project.days_left
        return :behind if days.zero?

        needed = (to_go * 60.0 / days / 5).ceil * 5
        pledged = project.pace_minutes || goal.pace_minutes(from: project.hours_start)
        needed <= pledged ? :on_track : :behind
      end
  end
end
