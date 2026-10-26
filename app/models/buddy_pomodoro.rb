# A pomodoro two buddies do together: one starts it, the other joins, and both count down to the same end.
class BuddyPomodoro < ApplicationRecord
  LENGTHS = [ 15, 25, 45, 60, 90 ].freeze

  belongs_to :pair
  belongs_to :started_by, class_name: "Project"

  validates :minutes, inclusion: { in: LENGTHS }

  scope :live, -> { where(started_at: ..Time.current).order(started_at: :desc) }

  def ends_at
    started_at + minutes.minutes
  end

  def live?(now = Time.current)
    now < ends_at
  end

  # Whether this project is in it: whoever started it is, and the other once they've joined.
  def in?(project)
    project == started_by || joined_at.present?
  end
end
