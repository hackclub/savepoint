# How the landing FAQ is read (D-094), in the admin home's sign-ups section: per question the opens, the median seconds it
# stayed open and the total minutes. Every question on the page is listed, so one nobody opens shows as zero. Most opens first.
class FaqStats
  Row = Data.define(:key, :question, :opens, :median_seconds, :total_minutes)

  def rows
    reads = FaqRead.group(:key).pluck(:key, Arel.sql("count(*)"), Arel.sql("percentile_cont(0.5) within group (order by seconds)"), Arel.sql("sum(seconds)"))
                   .to_h { |key, opens, median, total| [ key, [ opens, median.to_f, total ] ] }
    Faq.questions.map do |key, question|
      opens, median, total = reads.fetch(key, [ 0, nil, 0 ])
      Row.new(key:, question:, opens:, median_seconds: median&.round(1), total_minutes: (total / 60.0).round(1))
    end.sort_by.with_index { |row, index| [ -row.opens, index ] }
  end

  def any? = FaqRead.exists?
end
