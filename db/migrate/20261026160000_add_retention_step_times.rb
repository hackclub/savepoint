# D-078 item 2: the times the drop-off analysis couldn't see.
#   projects.first_coded_at: the start of the first span of counted time (set by the Hackatime sync).
#   projects.hackatime_picked_at: when the first Hackatime project was linked (picked, or linked itself).
#   users.hackatime_linked_at: when Hackatime was linked.
#   users.onboarding_step_times: { "2" => time, ... } the first time each onboarding step was reached.
# The pledge needs no column: a project is created at the pledge, so projects.created_at is that moment.
class AddRetentionStepTimes < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :first_coded_at, :datetime
    add_column :projects, :hackatime_picked_at, :datetime
    add_column :users, :hackatime_linked_at, :datetime
    add_column :users, :onboarding_step_times, :jsonb, default: {}, null: false

    # The only step time stored so far is the furthest one, so that is the one that can be filled in exactly. The
    # others stay missing. first_coded_at is filled in by the sync (it rebuilds from the first day when it's missing),
    # because only Hackatime's spans have the minute.
    execute <<~SQL
      update users
      set onboarding_step_times = jsonb_build_object(onboarding_step_reached::text, to_char(onboarding_step_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
      where onboarding_step_reached is not null and onboarding_step_at is not null
    SQL
  end

  def down
    remove_column :users, :onboarding_step_times
    remove_column :users, :hackatime_linked_at
    remove_column :projects, :hackatime_picked_at
    remove_column :projects, :first_coded_at
  end
end
