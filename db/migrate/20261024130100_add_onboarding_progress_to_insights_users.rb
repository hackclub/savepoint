# insights.users gains how far the participant got through onboarding. The columns go at the end, after last_seen_path.
class AddOnboardingProgressToInsightsUsers < ActiveRecord::Migration[8.1]
  def up
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
        onboarding_step_at
      from public.users
    SQL
  end

  def down
    # create or replace can't drop columns, so the earlier shape is built again.
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
        last_seen_path
      from public.users
    SQL
  end
end
