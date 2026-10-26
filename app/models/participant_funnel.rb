# The participants' funnel from signing in to claiming a prize, the one the analytics service shows, counted from the
# insights views (CreateInsightsViews): each step counts only people who reached every step before it, admins left out.
# The admin MCP's funnel tool and the admin home (AdminSummary) both read it here.
class ParticipantFunnel
  # [ key, label ]: the steps of the funnel, as save-point-analytics' shared/funnel.ts names them.
  STEPS = [ %w[signed_in Signed\ in], %w[pledged Pledged\ a\ project], %w[linked Linked\ Hackatime], %w[editor_sent Editor\ sent\ time],
            %w[set_up Picked\ a\ Hackatime\ project],
            %w[first_20 Built\ their\ first\ 20\ minutes], %w[past_5h Past\ 5\ hours], %w[past_10h Past\ 10\ hours], %w[shipped Shipped],
            %w[approved Ship\ approved], %w[claimed Claimed\ a\ prize] ].freeze

  # Editor sent time is a side look, not a gate: someone can pick a project before we recorded what Hackatime showed
  # (the column is new), so picking is measured against linking, not against it.
  AFTER = { "set_up" => "linked" }.freeze

  # The SHA-256 (hex) of each admin's Slack ID, as insights.users.slack_hash holds them.
  def self.admin_hashes = Rails.configuration.x.admin_slack_ids.to_a.map { Digest::SHA256.hexdigest(it) }

  # Who is waiting, not lost, at the two last steps (the funnel's own JSON, ParticipantFunnel.run, doesn't carry it):
  # `approved` is people past 10 hours who have shipped, have no approved ship and have a ship in review right now (their
  # newest one), and `claimed` is people with an approved ship who haven't claimed a prize yet. `funnel` is a run's answer.
  def self.waiting(funnel)
    counts = funnel.fetch(:steps).to_h { |step| [ step[:key], step[:count] ] }
    # The admins' hashes go in as one bound array literal ('{…}'), not pasted into the SQL.
    query = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, "{#{admin_hashes.join(",")}}" ])
      select count(*) from (
        select distinct on (user_id) user_id, status from insights.ships order by user_id, created_at desc, ship_id desc
      ) newest
      where status = 'in_review'
        and user_id in (select user_id from insights.users where slack_hash is null or not (slack_hash = any(?::text[])))
        and user_id in (select user_id from insights.ships group by user_id having count(*) filter (where status = 'approved') = 0)
    SQL
    in_review = ActiveRecord::Base.connection.select_value(query).to_i
    { approved: [ in_review, counts["shipped"] - counts["approved"] ].min, claimed: counts["approved"] - counts["claimed"] }
  end

  def self.run
    connection = ActiveRecord::Base.connection
    hashes = admin_hashes
    list = hashes.empty? ? "'{}'::text[]" : "array[#{hashes.map { connection.quote(it) }.join(", ")}]::text[]"
    row = connection.select_one(sql(list, connection.quote(Program::FIRST_STREAK_DATE.to_s)))
    counts = STEPS.map { |key, label| [ key, label, row.fetch(key).to_i ] }
    steps = counts.each_with_index.map do |(key, label, count), index|
      previous = counts.find { it[0] == AFTER[key] }&.last || counts[index - 1][2] unless index.zero?
      { key:, label:, count:, previous:, lost: (previous - count if previous), kept_percent: (previous&.positive? ? (count * 1000.0 / previous).round / 10.0 : nil) }
    end
    { participants: counts.first[2], steps: }
  end

  # Each step follows its definition in Metric (app/models/metric.rb), over participants only. A step counts people
  # (distinct user IDs), so one person with two projects counts once.
  def self.sql(admin_hashes, start)
    <<~SQL
      with people as (
        select user_id, hackatime_linked from insights.users
        where slack_hash is null or not (slack_hash = any(#{admin_hashes}))
      ),
      pledged as (
        select user_id from people where user_id in (select user_id from insights.projects)
      ),
      linked as (
        select user_id from people join pledged using (user_id) where hackatime_linked
      ),
      editor_sent as (
        select user_id from linked where user_id in (select user_id from insights.projects where hackatime_seen_seconds > 0)
      ),
      set_up as (
        select user_id from linked where user_id in (select user_id from insights.projects where hackatime_project_count > 0)
      ),
      first_20 as (
        select user_id from set_up where user_id in (select user_id from insights.streak_activities where coded_seconds >= #{StreakActivity::DAILY_GOAL_SECONDS})
      ),
      hours as (
        select user_id, sum(coded_seconds) as seconds from insights.streak_activities where activity_date >= #{start}::date group by user_id
      ),
      past_5h as (
        select user_id from first_20 join hours using (user_id) where seconds >= #{5 * 3600}
      ),
      past_10h as (
        select user_id from past_5h join hours using (user_id) where seconds >= #{Program::HOURS_PER_REWARD * 3600}
      ),
      shipped as (
        select user_id from past_10h where user_id in (select user_id from insights.ships)
      ),
      approved as (
        select user_id from shipped where user_id in (select user_id from insights.ships where status = 'approved')
      ),
      claimed as (
        select user_id from approved where user_id in (select user_id from insights.orders)
      )
      select
        (select count(*) from people) as signed_in,
        (select count(*) from pledged) as pledged,
        (select count(*) from linked) as linked,
        (select count(*) from editor_sent) as editor_sent,
        (select count(*) from set_up) as set_up,
        (select count(*) from first_20) as first_20,
        (select count(*) from past_5h) as past_5h,
        (select count(*) from past_10h) as past_10h,
        (select count(*) from shipped) as shipped,
        (select count(*) from approved) as approved,
        (select count(*) from claimed) as claimed
    SQL
  end
end
