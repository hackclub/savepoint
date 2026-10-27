# insights.faq_reads gains the browser's random reader_id (D-095). It names no person: it is made in the browser and linked to no user.
class AddReaderIdToInsightsFaqReads < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      create or replace view insights.faq_reads as
      select id as faq_read_id, key as question_key, seconds, created_at, reader_id
      from public.faq_reads
    SQL
  end

  def down
    execute "drop view if exists insights.faq_reads"
    execute <<~SQL
      create view insights.faq_reads as
      select id as faq_read_id, key as question_key, seconds, created_at
      from public.faq_reads
    SQL
  end
end
