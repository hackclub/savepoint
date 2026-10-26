namespace :metrics do
  # Rebuilds every day of Save Point so far from what's dated (Metric), for when the snapshots start late or a
  # metric's added. Today's is taken too, so the undated ones start now.
  #
  #   bin/rails metrics:backfill
  desc "Snapshot every day of Save Point so far"
  task backfill: :environment do
    puts "#{Metric.backfill!} numbers written for #{(Program::DATES.begin..Date.current).count} days"
  end
end
