# insights.nps_responses (D-118) for the admin MCP tools: every NPS answer with its score and free text. A person is a user
# ID, as in the other views. No name, email or Slack ID.
class AddNpsResponsesToInsightsViews < ActiveRecord::Migration[8.1]
  def up
    execute "create schema if not exists insights"
    execute <<~SQL
      create or replace view insights.nps_responses as
      select id as nps_response_id, score, doing_well, improve, anything_else, created_at, user_id, project_id
      from public.nps_responses
    SQL
  end

  def down
    execute "drop view if exists insights.nps_responses"
  end
end
