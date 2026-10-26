# One row for each day a signed-in participant opened the site (D-076): no path, no time of day. Auto-linking can attach a
# Hackatime project that isn't the game, so Hackatime time alone overstates who's building. This is the other half: of the
# builders on a day, how many also came to the site. Days are streak days (StreakActivity.streak_date_for: 2am to 2am in
# their timezone), so a row lines up with that user's StreakActivity row. History starts the day this shipped.
class SiteDay < ApplicationRecord
  belongs_to :user

  class << self
    # Notes that this person is here today. Once a day in effect: the unique index turns every later call into nothing.
    def record!(user, now = Time.current)
      insert_all([ { user_id: user.id, date: StreakActivity.streak_date_for(now, user.timezone), created_at: now } ], unique_by: %i[user_id date])
    end

    # Per day since the first streak day (oldest first): the participants who built Growth::ACTIVE_SECONDS or more
    # (D-075) and how many of them also opened the site that day. Admins aren't counted (D-032).
    def builders_by_date
      builders = StreakActivity.where(activity_date: Program::FIRST_STREAK_DATE.., coded_seconds: Growth::ACTIVE_SECONDS..)
                               .where(user_id: User.participants.select(:id))
      on_site = builders.joins("inner join site_days on site_days.user_id = streak_activities.user_id and site_days.date = streak_activities.activity_date")
      built = builders.group(:activity_date).count
      seen = on_site.group(:activity_date).count
      built.keys.sort.map { |date| { date:, builders: built[date], on_site: seen.fetch(date, 0) } }
    end
  end
end
