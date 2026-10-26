require "test_helper"

class StreakSweepJobTest < ActiveJob::TestCase
  test "D-086: it syncs everyone tracking, spread over a few minutes" do
    link_hackatime(users(:orpheus))
    users(:orpheus).project.update!(hackatime_projects: [ "rhythm-game" ])

    assert_enqueued_with(job: StreakSyncJob, args: [ users(:orpheus).id ]) { StreakSweepJob.perform_now }
    queued = enqueued_jobs.find { |job| job[:job] == StreakSyncJob }
    assert_operator queued[:at].to_f - Time.current.to_f, :<=, StreakSweepJob::SPREAD.to_i + 5 if queued[:at]
  end

  test "D-086: the sweep runs every 10 minutes" do
    sweep = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "streak_sweep")

    assert_equal "every 10 minutes", sweep["schedule"]
  end
end
