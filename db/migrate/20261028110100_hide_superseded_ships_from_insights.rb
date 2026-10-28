# D-109: insights.ships leaves out ships the participant replaced (status "superseded"), so the analytics repo's counts read
# only ships that stand. The columns are unchanged (UpdateInsightsShipsForFraudStage).
class HideSupersededShipsFromInsights < ActiveRecord::Migration[8.1]
  VIEW = <<~SQL
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

  def up
    # A database made from schema.rb has no views (tests make them, see InsightsViewsTest).
    return unless select_value("select to_regclass('insights.ships')::text")

    execute "#{VIEW.chomp}\n    where s.status <> 'superseded'"
  end

  def down
    return unless select_value("select to_regclass('insights.ships')::text")

    execute VIEW
  end
end
