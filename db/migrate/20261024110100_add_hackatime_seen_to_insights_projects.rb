# insights.projects (CreateInsightsViews) gains what Hackatime showed the participant: how many projects it listed and
# their seconds (Project#available_hackatime_projects=), and how many it listed when we first looked (the baseline).
# Counts and times only: no column names a person or a Hackatime project.
class AddHackatimeSeenToInsightsProjects < ActiveRecord::Migration[8.1]
  def up
    # A database made from schema.rb (which doesn't dump views) has the old migrations marked done without their views.
    execute "create schema if not exists insights"

    execute <<~SQL
      create or replace view insights.projects as
      select
        id as project_id,
        user_id,
        created_at,
        signed_on,
        json_array_length(hackatime_projects) as hackatime_project_count,
        json_array_length(hackatime_baseline) as hackatime_baseline_count,
        hackatime_seen_count,
        hackatime_seen_seconds,
        hackatime_seen_at
      from public.projects
    SQL
  end

  def down
    # create or replace can't drop columns, so the earlier shape is built again.
    execute "drop view if exists insights.projects"
    execute <<~SQL
      create view insights.projects as
      select
        id as project_id,
        user_id,
        created_at,
        signed_on,
        json_array_length(hackatime_projects) as hackatime_project_count
      from public.projects
    SQL
  end
end
