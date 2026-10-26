# Hourly: today's numbers (Metric), so by the end of the day the day's on record.
class MetricSnapshotJob < ApplicationJob
  def perform
    Metric.snapshot!
  end
end
