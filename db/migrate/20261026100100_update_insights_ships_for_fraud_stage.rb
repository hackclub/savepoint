# D-063: insights.ships keeps its contract (status in_review, approved, rejected for changes needed) while Ship gains
# awaiting_fraud and a final rejected. A ship waiting for its fraud check still reads in_review, and any rejection
# reads rejected. The new `stage` column holds the stored status. Change the analytics repo's contract/schema.rb with it.
class UpdateInsightsShipsForFraudStage < ActiveRecord::Migration[8.1]
  def up
    # A database made from schema.rb has no views (tests make them, see InsightsViewsTest).
    return unless select_value("select to_regclass('insights.ships')::text")

    execute <<~SQL
      create or replace view insights.ships as
      select
        s.id as ship_id,
        s.project_id,
        p.user_id,
        (case s.status when 'awaiting_fraud' then 'in_review' when 'changes_needed' then 'rejected' else s.status end)::varchar as status,
        s.hours,
        s.approved_hours,
        s.created_at,
        s.decided_at,
        s.status as stage
      from public.ships s
      join public.projects p on p.id = s.project_id
    SQL
  end

  def down
    return unless select_value("select to_regclass('insights.ships')::text")

    execute "drop view insights.ships"
    execute <<~SQL
      create view insights.ships as
      select s.id as ship_id, s.project_id, p.user_id, s.status, s.hours, s.approved_hours, s.created_at, s.decided_at
      from public.ships s
      join public.projects p on p.id = s.project_id
    SQL
  end
end
