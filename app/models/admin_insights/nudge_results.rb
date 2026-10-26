# Whether the bot's nudges got people building, for the admin home (AdminSummary). Of the delivered, real nudges that
# aren't cheers (the set Metric counts as "nudges"), the share where the person coded any time (StreakActivity
# coded_seconds above 0) on the day it was sent or the day after. Only nudges sent two or more days ago count, so both
# days are done. This is a plain before-and-after, not the bandit's own reward (Nudge#reward, built 20 minutes in 6 hours).
# Kinds with fewer than ENOUGH nudges are folded into "other kinds". Participants only.
module AdminInsights
  class NudgeResults
    ENOUGH = 5

    def self.call(today: Date.current) = new(today).call

    def initialize(today)
      @today = today
    end

    # { total: { n:, built:, percent: }, kinds: [ { kind:, n:, built:, percent: } ] }, the biggest kind first.
    def call
      rows = nudges.map { |user_id, kind, sent_at| [ kind, built_on.include?([ user_id, sent_at.to_date ]) || built_on.include?([ user_id, sent_at.to_date + 1 ]) ] }
      by_kind = rows.group_by(&:first).map { |kind, kind_rows| tally(kind, kind_rows) }.sort_by { |row| [ -row[:n], row[:kind] ] }
      small, big = by_kind.partition { |row| row[:n] < ENOUGH }
      kinds = big + (small.any? ? [ tally("other kinds", rows.select { |kind, _| small.any? { |row| row[:kind] == kind } }) ] : [])
      { total: tally("all", rows).except(:kind), kinds: }
    end

    private
      def tally(kind, rows)
        built = rows.count(&:last)
        { kind:, n: rows.size, built:, percent: (rows.empty? ? nil : (built * 100.0 / rows.size).round) }
      end

      def nudges
        Nudge.delivered.real.where.not(kind: "cheer").where(user_id: participant_ids).where(sent_at: ...(@today - 1).beginning_of_day)
             .pluck(:user_id, :kind, :sent_at)
      end

      def built_on
        @built_on ||= StreakActivity.where(user_id: participant_ids, coded_seconds: 1..).pluck(:user_id, :activity_date).to_set
      end

      def participant_ids = User.participants.select(:id)
  end
end
