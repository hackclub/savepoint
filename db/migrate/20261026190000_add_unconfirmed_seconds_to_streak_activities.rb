# D-084: time on a Hackatime project that linked itself is kept (so confirming counts it at once) but doesn't count until
# the person confirms it. coded_seconds is what counts; unconfirmed_seconds is the held time.
class AddUnconfirmedSecondsToStreakActivities < ActiveRecord::Migration[8.1]
  def up
    add_column :streak_activities, :unconfirmed_seconds, :integer, default: 0, null: false

    # Links that are still auto-linked (hackatime_auto_linked: nobody pressed Keep it or picked by hand) hold their time.
    execute <<~SQL
      update streak_activities
      set unconfirmed_seconds = coded_seconds, coded_seconds = 0
      where coded_seconds > 0
        and user_id in (select user_id from projects where hackatime_auto_linked = true)
    SQL
  end

  def down
    execute "update streak_activities set coded_seconds = coded_seconds + unconfirmed_seconds"
    remove_column :streak_activities, :unconfirmed_seconds
  end
end
