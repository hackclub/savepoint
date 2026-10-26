# The insights views (CreateInsightsViews) for UTM attribution (D-043): insights.users gains the three main tags, and
# insights.visits holds the tagged visits. Like the views there, no column names a person.
class AddUtmToInsightsViews < ActiveRecord::Migration[8.1]
  def up
    # A database made from schema.rb (which doesn't dump views) has the old migration marked done without its schema.
    execute "create schema if not exists insights"

    execute <<~SQL
      create or replace view insights.users as
      select
        id as user_id,
        created_at,
        encode(sha256(slack_id::bytea), 'hex') as slack_hash,
        (hackatime_uid is not null and hackatime_access_token is not null) as hackatime_linked,
        current_streak,
        (slack_muted_at is not null) as slack_muted,
        utm_source,
        utm_medium,
        utm_campaign
      from public.users
    SQL

    execute <<~SQL
      create or replace view insights.visits as
      select id as visit_id, utm_source, utm_medium, utm_campaign, utm_content, utm_term, path, created_at
      from public.visits
    SQL
  end

  def down
    execute "drop view if exists insights.visits"
    # create or replace can't drop columns, so the old shape is built again.
    execute "drop view if exists insights.users"
    execute <<~SQL
      create view insights.users as
      select
        id as user_id,
        created_at,
        encode(sha256(slack_id::bytea), 'hex') as slack_hash,
        (hackatime_uid is not null and hackatime_access_token is not null) as hackatime_linked,
        current_streak,
        (slack_muted_at is not null) as slack_muted
      from public.users
    SQL
  end
end
