class RebuildStreaksFromSignUp < ActiveRecord::Migration[8.1]
  # D-065: hours count from each participant's sign-up, not the launch moment. Queues a rebuild of every day for everyone
  # with a tracking project, so time before their sign-up drops out, the same as bin/rails streaks:rebuild_launch_moment
  # (D-055). A day that was complete stays complete, so nobody's cheered twice.
  def up
    User.joins(:project).where.not(hackatime_uid: nil).find_each do |user|
      StreakSyncJob.perform_later(user.id, from_start: true) if user.project.tracking?
    end
  end

  def down
    # Nothing to undo: the jobs only rewrote hours from Hackatime.
  end
end
