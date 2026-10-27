# How long someone built on one streak day, from Hackatime. Only time on the Hackatime projects linked to their
# project counts, and a day counts towards the streak at DAILY_GOAL_SECONDS. Days run 2am to 2am in their timezone,
# so building past midnight still counts for the night before. (From Stardance's streaks.)
class StreakActivity < ApplicationRecord
  DAILY_GOAL_SECONDS = 20 * 60

  belongs_to :user

  validates :activity_date, presence: true, uniqueness: { scope: :user_id }
  validates :coded_seconds, numericality: { greater_than_or_equal_to: 0 }

  scope :completed, -> { where(coded_seconds: DAILY_GOAL_SECONDS..) }
  # D-084: a day's time on a link that linked itself and isn't confirmed yet (unconfirmed_seconds) is kept apart from
  # coded_seconds, which is all that counts anywhere (hours, streaks, DAU). D-087: coding_seconds is how much of the day's
  # time (held or not) Hackatime files under coding, and the DAU counts that; nil is not asked yet, and reads as all of it.
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
      # D-084: a link nobody has confirmed (it linked itself) is still synced, but its time is held, not counted.
      held = !project.hackatime_confirmed?
      CodedBucket.rewrite_for(user, counted, held:, coding_share: coding_share_for_pieces(user, project, counted))

      just_completed = []
      (start_date..today).each do |date|
        seconds = daily_seconds.fetch(date, 0)
        counted_seconds, held_seconds = held ? [ 0, seconds ] : [ seconds, 0 ]
        coding = (seconds * coding_ratio(user, project, counted, *streak_day_window(date, user.timezone))).round if seconds.positive?
        just_completed << date if write_day(user, date, counted_seconds, held_seconds, coding) && date >= today - 1
      end

      user.update_column(:streak_synced_at, Time.current)
      user.recalculate_streak!
      Nudge::Cheer.queue(user, just_completed.max) if just_completed.any?
    end

    # D-084: the person confirmed their link, so the time held for it counts, without asking Hackatime.
    def release_held!(user)
      CodedBucket.release_held!(user)
      user.streak_activities.where("unconfirmed_seconds > 0")
          .update_all("coded_seconds = coded_seconds + unconfirmed_seconds, unconfirmed_seconds = 0, updated_at = CURRENT_TIMESTAMP")
    end

    # D-091: time held on a hand-picked link (D-087 held the doubtful ones) counts. Moves it into the counted seconds of
    # each person whose project isn't an unconfirmed auto-link, and recalculates their streak. Safe to run again: it
    # only moves what is still held. Returns the ids of the people it released.
    def release_held_on_hand_picked_links!
      hand_picked = User.where(id: Project.where(hackatime_auto_linked: false).select(:user_id))
      ids = (CodedBucket.where(user_id: hand_picked).where("unconfirmed_seconds > 0").distinct.pluck(:user_id) |
             where(user_id: hand_picked).where("unconfirmed_seconds > 0").distinct.pluck(:user_id))
      User.where(id: ids).find_each do |user|
        release_held!(user)
        user.recalculate_streak!
      end
      ids
    end

    def streak_date_for(time, timezone)
      (time.in_time_zone(timezone.presence || "UTC") - 2.hours).to_date
    end

    private
      # D-087: what share (0 to 1) of the time in `spans` between two moments Hackatime files under coding, from its stats
      # (Hackatime.coding_seconds), capped at 1 because its stats and its spans count a gap or two differently. 1 when it
      # can't say, so nothing vanishes while Hackatime is slow. One request, and none for a window with no time in it.
      def coding_ratio(user, project, spans, from, to)
        from = [ from, project.hours_start, Program::STARTS_AT ].max
        return 1.0 if from >= to

        total = spans.sum { |span| [ [ span["end_time"].to_f, to.to_f ].min - [ span["start_time"].to_f, from.to_f ].max, 0 ].max }
        return 1.0 if total < 1

        coding = Hackatime.coding_seconds(user, project.hackatime_projects, from:, to:)
        coding ? [ coding.fdiv(total), 1.0 ].min : 1.0
      end

      # The coding share of the 5-minute pieces CodedBucket keeps: asked for the last 24 hours (what the DAU counts) and the
      # stretch before it, so two requests.
      def coding_share_for_pieces(user, project, spans, now: Time.current)
        from = CodedBucket.floor(now - CodedBucket::REWRITE)
        split = now - 24.hours
        before = coding_ratio(user, project, spans, from, split)
        since = coding_ratio(user, project, spans, split, now + 1.minute)
        ->(at) { at < split ? before : since }
      end

      # A streak day runs 2am to 2am in the person's timezone.
      def streak_day_window(date, timezone)
        zone = ActiveSupport::TimeZone[timezone.presence || "UTC"]
        [ zone.local(date.year, date.month, date.day, 2), zone.local((date + 1).year, (date + 1).month, (date + 1).day, 2) ]
      end

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
      def write_day(user, date, seconds, held_seconds = 0, coding_seconds = nil)
        attempts = 0
        begin
          record = find_or_initialize_by(user_id: user.id, activity_date: date)
          return false if record.persisted? && record.coded_seconds == seconds && record.unconfirmed_seconds == held_seconds && record.coding_seconds == coding_seconds

          completed_before = record.persisted? && record.completed?
          record.update!(coded_seconds: seconds, unconfirmed_seconds: held_seconds, coding_seconds:)
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
