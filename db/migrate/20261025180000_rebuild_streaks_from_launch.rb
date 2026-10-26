class RebuildStreaksFromLaunch < ActiveRecord::Migration[8.1]
  # D-055: days synced before it count time from before the launch moment, and miss a western participant's time on
  # the day before the launch date. Queues a rebuild of every day for everyone with a tracking project, the same as
  # bin/rails streaks:rebuild_launch_moment. A day that was complete stays complete, so nobody's cheered twice.
  def up
    User.joins(:project).where.not(hackatime_uid: nil).find_each do |user|
      StreakSyncJob.perform_later(user.id, from_start: true) if user.project.tracking?
    end
  end

  def down
    # Nothing to undo: the jobs only rewrote hours from Hackatime.
  end
end
