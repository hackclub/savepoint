class AddBuiltOnToNudges < ActiveRecord::Migration[8.1]
  def change
    # For a cheer (Nudge::Cheer): the streak day it's for, so each day gets one at most and it's scored on the day
    # after.
    add_column :nudges, :built_on, :date
    add_index :nudges, [ :user_id, :built_on ]
  end
end
