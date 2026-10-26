# How long someone built on one streak day, from Hackatime. Only time on the Hackatime projects linked to their
# project counts, and a day counts towards the streak at DAILY_GOAL_SECONDS. Days run 2am to 2am in their timezone,
# so building past midnight still counts for the night before. (From Stardance's streaks.)
class StreakActivity < ApplicationRecord
  DAILY_GOAL_SECONDS = 20 * 60

  belongs_to :user

  validates :activity_date, presence: true, uniqueness: { scope: :user_id }
  validates :coded_seconds, numericality: { greater_than_or_equal_to: 0 }

  scope :completed, -> { where(coded_seconds: DAILY_GOAL_SECONDS..) }
  scope :for_range, ->(range) { where(activity_date: range) }

  def completed?
    coded_seconds >= DAILY_GOAL_SECONDS
  end

  class << self
    # Rewrites every day since the day before the last sync (or since Program::FIRST_STREAK_DATE) from
    # Hackatime's heartbeat spans, then the streak. Time before the project's hours_start never counts (D-055, D-065): spans are
    # clipped at that moment. `from_start` ignores the last sync and rebuilds every day (what refresh_streak! and the
    # one-off streaks:rebuild_launch_moment and the D-065 migration do). Days only change, so a rebuild cheers nobody twice: a day that was
    # complete stays complete, and Reward.earn is once per key. A day (today or yesterday) that's just reached its 20 minutes
    # gets a cheer from the bot (Nudge::Cheer): one cheer, for the latest such day, when a first sync finds both.
    # It's queued after the streak's rewards, so a reward's DM goes first and the cheer waits its hour. Nothing
    # happens without Hackatime linked and projects picked.
    def sync_for_user!(user, from_start: false)
      project = user.project
      return unless project&.tracking?

      today = streak_date_for(Time.current, user.timezone)
      from_start ||= missing_first_coded?(user, project)
      synced_on = streak_date_for(user.streak_synced_at, user.timezone) - 1 if user.streak_synced_at && !from_start
      start_date = [ synced_on || Program::FIRST_STREAK_DATE, Program::FIRST_STREAK_DATE ].max

      # Hackatime bounds spans by its own calendar days (midnight to midnight, its time), while streak days run 2am
      # to 2am in yours: so it's asked for a day either side, or tonight's building would be tomorrow by its clock
      # and left out until the next sync.
      spans = Hackatime.heartbeat_spans(user, project.hackatime_projects, start_date: start_date - 1, end_date: today + 2)
      counted = clip_to_start(spans, project.hours_start)
      daily_seconds = bucket_spans_by_streak_day(counted, user.timezone)
      note_first_coded(project, counted)

      just_completed = []
      (start_date..today).each do |date|
        seconds = daily_seconds.fetch(date, 0)
        just_completed << date if write_day(user, date, seconds) && date >= today - 1
      end

      user.update_column(:streak_synced_at, Time.current)
      user.recalculate_streak!
      Nudge::Cheer.queue(user, just_completed.max) if just_completed.any?
    end

    def streak_date_for(time, timezone)
      (time.in_time_zone(timezone.presence || "UTC") - 2.hours).to_date
    end

    private
      # The start of the first counted span, kept once (projects.first_coded_at). The sync reads every day since the
      # last one, so a person's first minute is in the first sync that finds time.
      def note_first_coded(project, counted)
        return if project.first_coded_at

        first = counted.select { |span| span["duration"].to_f.positive? }.map { |span| span["start_time"].to_f }.min
        project.update_columns(first_coded_at: Time.zone.at(first)) if first
      end

      # Someone with counted days from before first_coded_at existed has their sync read from the first day once, which
      # is the one place their first minute is.
      def missing_first_coded?(user, project)
        project.first_coded_at.nil? && user.streak_activities.where(coded_seconds: 1..).exists?
      end

      # Saves one day and says whether this write took it past the goal. Two syncs for one user can run at once
      # (the sweep and an on-demand sync), and both may find no row for a day. The loser hits the unique index or
      # the uniqueness validation, so it looks the row up again and writes onto the winner's. A day the winner
      # completed counts as completed before, so only one sync cheers.
      def write_day(user, date, seconds)
        attempts = 0
        begin
          record = find_or_initialize_by(user_id: user.id, activity_date: date)
          return false if record.persisted? && record.coded_seconds == seconds

          completed_before = record.persisted? && record.completed?
          record.update!(coded_seconds: seconds)
          record.completed? && !completed_before
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
          raise if error.is_a?(ActiveRecord::RecordInvalid) && !error.record.errors.of_kind?(:activity_date, :taken)
          raise if (attempts += 1) >= 2

          retry
        end
      end

      # D-055, D-065: only time after `start` (Project#hours_start: sign-up or launch, or a reviewer's override) counts.
      # A span across it keeps its later part, one before it goes.
      def clip_to_start(spans, start)
        launch = start.to_f
        spans.filter_map do |span|
          next span if span["start_time"].to_f >= launch

          finish = span["end_time"].to_f
          next if finish <= launch

          span.merge("start_time" => launch, "duration" => finish - launch)
        end
      end

      # Seconds per streak day. A span across 2am is split between the two days.
      def bucket_spans_by_streak_day(spans, timezone)
        tz = timezone.presence || "UTC"
        buckets = Hash.new(0)

        spans.each do |span|
          duration = span["duration"].to_f
          next if duration <= 0

          start_local = Time.at(span["start_time"].to_f).in_time_zone(tz)
          end_local = Time.at(span["end_time"].to_f).in_time_zone(tz)

          if (start_local - 2.hours).to_date == (end_local - 2.hours).to_date
            buckets[(start_local - 2.hours).to_date] += duration.round
          else
            remaining = duration
            cursor = start_local

            while remaining > 0
              day = (cursor - 2.hours).to_date
              next_day = day + 1.day
              next_boundary = ActiveSupport::TimeZone[tz].local(next_day.year, next_day.month, next_day.day, 2, 0, 0)
              secs = [ next_boundary - cursor, remaining ].min
              buckets[day] += secs.round
              remaining -= secs
              cursor = next_boundary
            end
          end
        end

        buckets
      end
  end
end
