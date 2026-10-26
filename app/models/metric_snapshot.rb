# One of Save Point's numbers (Metric) on one day. Today's is rewritten hourly (MetricSnapshotJob), so it ends up
# as the day's final value; past days are kept as they were, or rebuilt (bin/rails metrics:backfill).
class MetricSnapshot < ApplicationRecord
  validates :key, inclusion: { in: Metric::KEYS }
end
