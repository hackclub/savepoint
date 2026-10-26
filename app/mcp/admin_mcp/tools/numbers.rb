module AdminMcp::Tools::Numbers
  # The admin home's sign-ups and history sections (once the Numbers page): Save Point's numbers day by day, the NPS and where sign-ups come from.
  class Metrics < AdminMcp::Tool
    reads "metrics", "Save Point's numbers",
          "What the admin home's day-by-day history shows: each metric (funnel counts, hours, builders, bandit nudges, and more) per day for the last `days` days, " \
          "builders per day and how many of them also opened the site (D-076, from the day it shipped), the NPS of the last 7 days with the newest answers (score, who by public name, the three answers), and where sign-ups come from (UTM source, " \
          "medium and campaign: landing-page visits, sign-ups, rate, and the untagged ones). Participants only.",
          { days: { type: "integer", minimum: 1, maximum: 120, description: "How many of the latest days. Default 14." } }

    def self.run(args, _caller)
      days, values = Metric.history
      shown = days.last(args[:days] || 14)
      { days: shown, metrics: Metric::DEFINITIONS.map { |definition| { key: definition.key, label: definition.label, cumulative: definition.cumulative,
                                                                         values: shown.map { values.dig(definition.key, it) } } },
        site_days: SiteDay.builders_by_date.last(args[:days] || 14), nps: nps, utm: utm }
    end

    def self.nps
      stats = NpsStats.new
      week = stats.last_7_days
      { last_7_days: { nps: week.nps, people: week.people, promoters: week.promoters, passives: week.passives, detractors: week.detractors },
        latest: stats.latest.map do |answer|
          { id: answer.id, score: answer.score, who: answer.user.public_name, at: answer.created_at, source: answer.source, project: answer.project&.title,
            **NpsResponse::QUESTIONS.keys.index_with { answer[it] } }
        end }
    end

    def self.utm
      stats = UtmStats.new
      { untagged_signups: stats.untagged, untagged_visits: stats.untagged_visits,
        untagged_signups_per_visit_percent: stats.untagged_rate&.round(1),
        rows: stats.rows.map { { source: it.source, medium: it.medium, campaign: it.campaign, visits: it.visits, signups: it.signups, signups_per_visit_percent: it.rate&.round(1) } } }
    end
  end

  # The Bandit page: how the bot's nudges are doing and what the bandit has learned.
  class Nudges < AdminMcp::Tool
    reads "nudges", "How the nudges are doing",
          "What the Bandit page shows: nudges sent, clicked and scored, the bandit against the holdout, each bucket's arms with the bandit's current guess, the " \
          "fixed nudges, sends per day, and the latest nudges (who by user ID, the arm, the message, the odds, clicks and result).",
          { recent: { type: "integer", minimum: 0, maximum: 100, description: "How many of the latest nudges. Default 20." } }

    def self.run(args, _caller)
      stats = Nudge::Stats.new
      { totals: row(stats.totals), muted_users: stats.muted_users, cannot_dm: stats.failed_dms, cannot_dm_details: stats.failed_dm_details, waiting_to_score: stats.waiting,
        policies: stats.policies.transform_values { row(it) },
        buckets: stats.buckets.transform_values { |arms| arms.map { |arm| { arm: arm[:arm], **row(arm[:row]), **arm.except(:arm, :row) } } },
        fixed: stats.fixed.map { |(kind, arm), row| { kind:, arm:, **row(row) } },
        daily: stats.daily,
        recent: stats.recent(args[:recent] || 20).map do |nudge|
          { id: nudge.id, user_id: nudge.user_id, sent_at: nudge.sent_at, kind: nudge.kind, bucket: nudge.bucket, arm: nudge.arm, holdout: nudge.holdout,
            text: nudge.text, propensity: nudge.propensity, clicks: nudge.clicks, reward: nudge.reward }
        end }
    end

    def self.row(row) = { **row.to_h, click_rate: row.click_rate, work_rate: row.work_rate, failed: row.failed }
  end

  # The public Stats page: totals across everyone, the funnel, who builds each day, and Growth.
  class PublicStats < AdminMcp::Tool
    reads "public_stats", "The public stats",
          "The numbers on the public /stats page: totals, the funnel, hours and builders per day, streaks, and Growth (who's building, in three groups: new, built yesterday too, back after days off, with the rates and projections). " \
          "Counts everyone, admins too, as the public page does."

    def self.run(_args, _caller) = ::PublicStats.cached
  end
end
