# insights.faq_reads (D-094) for the analytics tools: the same columns as the table, none of which names a person.
class AddFaqReadsToInsightsViews < ActiveRecord::Migration[8.1]
  def up
    execute "create schema if not exists insights"
    execute <<~SQL
      create or replace view insights.faq_reads as
      select id as faq_read_id, key as question_key, seconds, created_at
      from public.faq_reads
    SQL
  end

  def down
    execute "drop view if exists insights.faq_reads"
  end
end
