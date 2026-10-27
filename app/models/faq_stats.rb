# How the landing FAQ is read (D-094, D-095), in the admin home's sign-ups section: per question the people who opened it
# (distinct browser reader IDs), all opens, the average seconds each person spent on it, and the total minutes. Every
# question on the page is listed, so one nobody opens shows as zero. Most people first, then most opens.
# Reads from before the reader ID (D-095) have none: they count as opens and total minutes only, never as people.
class FaqStats
  Row = Data.define(:key, :question, :people, :opens, :average_seconds, :total_minutes)

  def rows
    reads = FaqRead.group(:key).pluck(
      :key, Arel.sql("count(*)"), Arel.sql("count(distinct reader_id)"),
      Arel.sql("coalesce(sum(seconds) filter (where reader_id is not null), 0)"), Arel.sql("sum(seconds)")
    ).to_h { |key, opens, people, identified, total| [ key, [ opens, people, identified, total ] ] }
    Faq.questions.map do |key, question|
      opens, people, identified, total = reads.fetch(key, [ 0, 0, 0, 0 ])
      Row.new(key:, question:, people:, opens:, average_seconds: (identified.to_f / people if people.positive?), total_minutes: (total / 60.0).round(1))
    end.sort_by.with_index { |row, index| [ -row.people, -row.opens, index ] }
  end

  def any? = FaqRead.exists?
end
