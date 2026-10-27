# Time someone coded, in 5-minute pieces, for the last few days only (D-086). StreakActivity keeps whole days, which can't
# answer "who built today (Eastern time)?" (D-092). The Hackatime sync rewrites the recent pieces from the spans it reads.
# `seconds` counts; `unconfirmed_seconds` is time held on a link nobody has confirmed (D-084), like StreakActivity's.
# `coding_seconds` (D-087) is how much of the piece Hackatime files under coding, held or not; nil is not asked yet, and reads as all of it.
class CodedBucket < ApplicationRecord
  SIZE = 5.minutes.to_i
  KEEP = 3.days
  # The sync reads at least 2 days back, so it can rewrite every piece from here on; the tile needs only today (D-092).
  REWRITE = 36.hours

  belongs_to :user

  class << self
    # Replaces the pieces from REWRITE ago on with those of `spans` ({ "start_time", "end_time" } in epoch seconds), held or
    # counted by `held`, and forgets the very old ones. `coding_share` says what share (0 to 1) of the time starting at a given
    # moment is coding (D-087).
    def rewrite_for(user, spans, held:, now: Time.current, coding_share: ->(_at) { 1.0 })
      from = floor(now - REWRITE)
      pieces = Hash.new(0)
      spans.each do |span|
        start = [ span["start_time"].to_f, from.to_f ].max
        finish = span["end_time"].to_f
        while start < finish
          boundary = (start.floor / SIZE + 1) * SIZE
          pieces[Time.zone.at(start.floor / SIZE * SIZE)] += [ boundary, finish ].min - start
          start = boundary
        end
      end

      transaction do
        where(user_id: user.id).where(bucket_at: ...(now - KEEP)).delete_all
        where(user_id: user.id, bucket_at: from..).delete_all
        rows = pieces.filter_map do |at, seconds|
          seconds = seconds.round
          next if seconds <= 0
          { user_id: user.id, bucket_at: at, seconds: held ? 0 : seconds, unconfirmed_seconds: held ? seconds : 0,
            coding_seconds: (seconds * coding_share.call(at)).round.clamp(0, seconds) }
        end
        insert_all(rows) if rows.any?
      end
    end

    # D-084: the person confirmed their link, so the held pieces count.
    def release_held!(user)
      where(user_id: user.id).where("unconfirmed_seconds > 0").update_all("seconds = seconds + unconfirmed_seconds, unconfirmed_seconds = 0")
    end

    # Per user: [user id, coding seconds that count, coding seconds held] since `since` (D-087: only coding). Whole 5-minute
    # pieces, so the window is exact to within one piece.
    def totals_since(since, user_ids)
      where(user_id: user_ids, bucket_at: floor(since)..).group(:user_id)
        .pluck(:user_id, Arel.sql("sum(case when seconds > 0 then coalesce(coding_seconds, seconds) else 0 end)"),
                         Arel.sql("sum(case when unconfirmed_seconds > 0 then coalesce(coding_seconds, unconfirmed_seconds) else 0 end)"))
    end

    def floor(time) = Time.zone.at(time.to_i / SIZE * SIZE)
  end
end
