namespace :streaks do
  # One time: streak days synced while a linked Hackatime project with a comma in its name matched nothing (the
  # spans filter split on commas) stay at zero, since a sync only rewrites days from the day before the last one.
  # Rebuilds every day from the start for everyone with such a project.
  #
  #   bin/rails streaks:rebuild_comma_projects
  desc "Rebuild streaks for everyone with a comma in a linked Hackatime project's name"
  task rebuild_comma_projects: :environment do
    users = User.joins(:project).where.not(hackatime_uid: nil).select { |user| user.project.hackatime_projects.any? { |name| name.include?(",") } }
    users.each(&:refresh_streak!)
    puts "queued a rebuild for #{users.size} #{"user".pluralize(users.size)}"
  end

  # One time, after D-055 deploys: days synced before it count time from before the launch moment and miss the
  # post-launch time of someone west of UTC on the day before the launch date. Queues a rebuild of every day, from the
  # first streak day, for everyone with a tracking project. The jobs only rewrite hours: a day that was complete stays
  # complete, so nobody gets a second cheer or reward.
  #
  #   bin/rails streaks:rebuild_launch_moment
  desc "Rebuild every streak day for everyone with a tracking project (D-055)"
  task rebuild_launch_moment: :environment do
    users = User.joins(:project).where.not(hackatime_uid: nil).select { |user| user.project.tracking? }
    users.each { |user| StreakSyncJob.perform_later(user.id, from_start: true) }
    puts "queued a rebuild for #{users.size} #{"user".pluralize(users.size)}"
  end
end
