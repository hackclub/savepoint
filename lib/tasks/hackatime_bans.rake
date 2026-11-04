namespace :hackatime do
  # D-151, once: bans everyone whose stored Hackatime trust level is red and who isn't banned. Safe to run again.
  #
  #   bin/rails hackatime:ban_red
  desc "Ban every unbanned user whose Hackatime trust level is red"
  task ban_red: :environment do
    banned = User.where(hackatime_trust_level: "red", banned_at: nil).find_each.count(&:ban_for_hackatime!)
    puts "Banned #{banned} user#{"s" unless banned == 1}."
  end
end
