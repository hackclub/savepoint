require "test_helper"

class SiteDayTest < ActiveSupport::TestCase
  DAY = Program::FIRST_STREAK_DATE + 1

  test "records a person once a day, however often they're seen" do
    user = users(:ana)
    now = Time.utc(2026, 11, 1, 12)

    assert_difference -> { SiteDay.count }, 1 do
      3.times { |i| user.touch_last_seen("/shop", now + (i * 2).minutes) }
    end
    assert_equal [ [ user.id, Date.new(2026, 11, 1) ] ], SiteDay.pluck(:user_id, :date)

    assert_difference -> { SiteDay.count }, 1 do
      user.touch_last_seen("/shop", now + 1.day)
    end
  end

  test "the day is the streak day in their timezone: 2am to 2am" do
    user = users(:ana)
    user.update!(timezone: "America/New_York")

    user.touch_last_seen("/", Time.utc(2026, 11, 2, 5, 30)) # 00:30 in New York: still the 1st
    assert_equal [ Date.new(2026, 11, 1) ], SiteDay.where(user:).pluck(:date)
  end

  test "compares who built with who also opened the site, leaving admins out" do
    builder_seen = built("seen")
    built("unseen")
    built("short", seconds: Growth::ACTIVE_SECONDS - 1)
    admin = users(:orpheus)
    admin.streak_activities.create!(activity_date: DAY, coded_seconds: 3600)
    original = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ admin.slack_id ]
    [ builder_seen, admin ].each { |user| SiteDay.create!(user:, date: DAY, created_at: Time.current) }
    SiteDay.create!(user: builder_seen, date: DAY + 1, created_at: Time.current)

    assert_equal [ { date: DAY, builders: 2, on_site: 1 } ], SiteDay.builders_by_date
  ensure
    Rails.configuration.x.admin_slack_ids = original
  end

  private
    def built(name, seconds: Growth::ACTIVE_SECONDS)
      User.create!(hca_id: "ident!site_#{name}", first_name: name).tap do |user|
        user.streak_activities.create!(activity_date: DAY, coded_seconds: seconds)
      end
    end
end
