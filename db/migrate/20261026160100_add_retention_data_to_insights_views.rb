# D-078 item 2: the insights views gain the step times, the goal prize, the buddy fields and the pace (projects and
# users), and two new views: nudges (no message text) and site_days. Counts, times and keys only: nothing names a person.
# Change the analytics repo's contract/schema.rb with it.
class AddRetentionDataToInsightsViews < ActiveRecord::Migration[8.1]
  def up
    # A database made from schema.rb (which doesn't dump views) has the old migrations marked done without their views.
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
        utm_campaign,
        last_seen_at,
        last_seen_path,
        onboarding_step_reached,
        onboarding_step_at,
        hackatime_linked_at,
        onboarding_step_times
      from public.users
    SQL

    # The pledge is created_at: a project is made at the pledge. paired_on is when the buddy pair began, never who.
    execute <<~SQL
      create or replace view insights.projects as
      select
        p.id as project_id,
        p.user_id,
        p.created_at,
        p.signed_on,
        json_array_length(p.hackatime_projects) as hackatime_project_count,
        json_array_length(p.hackatime_baseline) as hackatime_baseline_count,
        p.hackatime_seen_count,
        p.hackatime_seen_seconds,
        p.hackatime_seen_at,
        p.first_coded_at,
        p.hackatime_picked_at,
        p.prize_key,
        p.pace_minutes,
        p.buddy_invited,
        p.buddy_skipped,
        (select pr.started_on from public.pairs pr where p.id in (pr.first_project_id, pr.second_project_id)) as paired_on
      from public.projects p
    SQL

    # nudges: the bot's messages, without their text, the Slack message, or the link token.
    execute <<~SQL
      create or replace view insights.nudges as
      select id as nudge_id, user_id, kind, bucket, arm, holdout, sent_at, clicked_at, reward, opted_out_at
      from public.nudges
    SQL

    # site_days: each day a participant opened the site (D-076).
    execute <<~SQL
      create or replace view insights.site_days as
      select user_id, date
      from public.site_days
    SQL
  end

  def down
    execute "drop view if exists insights.site_days"
    execute "drop view if exists insights.nudges"

    # create or replace can't drop columns, so the earlier shapes are built again.
    execute "drop view if exists insights.projects"
    execute <<~SQL
      create view insights.projects as
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

    execute "drop view if exists insights.users"
    execute <<~SQL
      create view insights.users as
      select
        id as user_id,
        created_at,
        encode(sha256(slack_id::bytea), 'hex') as slack_hash,
        (hackatime_uid is not null and hackatime_access_token is not null) as hackatime_linked,
        current_streak,
        (slack_muted_at is not null) as slack_muted,
        utm_source,
        utm_medium,
        utm_campaign,
        last_seen_at,
        last_seen_path,
        onboarding_step_reached,
        onboarding_step_at
      from public.users
    SQL
  end
end
