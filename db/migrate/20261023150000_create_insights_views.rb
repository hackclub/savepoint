# The only part of this database the analytics service (hackclub/save-point-analytics) reads. It connects with
# Save Point's own login, read-only, and queries only the schema `insights` (D-041).
#
# Rules of every view here:
#   - No column holds a person's email, name, address, phone number, birthdate, Slack ID, or any token or secret.
#   - A person is a Save Point user ID, which means nothing outside Save Point.
#   - Admins are left out by the service, through slack_hash: the SHA-256 (hex) of the Slack ID. The ID never leaves.
#
# A change to a column these views read (users, projects, streak_activities, ships, orders) must update this
# migration and the analytics repo's contract/schema.rb together, or the view breaks.
class CreateInsightsViews < ActiveRecord::Migration[8.1]
  VIEWS = %w[users projects streak_activities ships orders].freeze

  def up
    execute "create schema if not exists insights"

    # users: every sign-in. Only whether a Hackatime token exists leaves, not the token.
    execute <<~SQL
      create or replace view insights.users as
      select
        id as user_id,
        created_at,
        encode(sha256(slack_id::bytea), 'hex') as slack_hash,
        (hackatime_uid is not null and hackatime_access_token is not null) as hackatime_linked,
        current_streak,
        (slack_muted_at is not null) as slack_muted
      from public.users
    SQL

    # projects: one per person.
    execute <<~SQL
      create or replace view insights.projects as
      select
        id as project_id,
        user_id,
        created_at,
        signed_on,
        json_array_length(hackatime_projects) as hackatime_project_count
      from public.projects
    SQL

    # streak_activities: the seconds coded on one day.
    execute <<~SQL
      create or replace view insights.streak_activities as
      select user_id, activity_date, coded_seconds
      from public.streak_activities
    SQL

    # ships: statuses are in_review, approved, rejected (shown to people as "changes needed"). No title, text, or link.
    execute <<~SQL
      create or replace view insights.ships as
      select
        s.id as ship_id,
        s.project_id,
        p.user_id,
        s.status,
        s.hours,
        s.approved_hours,
        s.created_at,
        s.decided_at
      from public.ships s
      join public.projects p on p.id = s.project_id
    SQL

    # orders: statuses are waiting and ordered. No address or recipient.
    execute <<~SQL
      create or replace view insights.orders as
      select
        o.id as order_id,
        o.project_id,
        p.user_id,
        o.status,
        o.hours,
        o.prize_key,
        o.created_at,
        o.ordered_at
      from public.orders o
      join public.projects p on p.id = o.project_id
    SQL
  end

  def down
    VIEWS.each { |view| execute "drop view if exists insights.#{view}" }
    execute "drop schema if exists insights"
  end
end
