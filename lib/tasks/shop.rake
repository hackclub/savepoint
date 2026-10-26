# What the shop would cost, from everyone's hours right now: whose hours cover their pick, and what those picks cost us.
#
#   bin/rails shop:forecast
namespace :shop do
  desc "Cost of everyone's picks at today's hours"
  task forecast: :environment do
    seconds = StreakActivity.where(activity_date: Program::FIRST_STREAK_DATE..).group(:user_id).sum(:coded_seconds)

    rows = Project.includes(:user).map do |project|
      hours = (seconds.fetch(project.user_id, 0) / 3600.0).round(1)
      { name: project.user.public_name, hours:, needed: project.hours_needed, pick: project.prize_short, price: project.chosen_prize.cost,
        afford: project.afford?(hours) }
    end

    puts format("%-14s %6s %7s  %-12s %7s  %s", "who", "hours", "needs", "pick", "price", "")
    rows.sort_by { |row| -row[:hours] }.each do |row|
      puts format("%-14s %6.1f %7.1f  %-12s %7s  %s", row[:name][0, 14], row[:hours], row[:needed], row[:pick],
                  "$#{row[:price]}", row[:afford] ? "covered" : "")
    end

    new_cost = rows.select { |row| row[:afford] }.sum { |row| row[:price] }
    puts
    puts "#{rows.count { |row| row[:afford] }} of #{rows.size} picks covered."
    puts "Shop, at today's hours:   $#{new_cost.round(2)}"
  end
end
