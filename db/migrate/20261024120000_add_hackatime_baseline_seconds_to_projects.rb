# The seconds each Hackatime project had when we noted the baseline, by name. A continued game keeps its old project
# name, so the names alone can't tell it from one you were never going to build on: what it gained since can.
class AddHackatimeBaselineSecondsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :hackatime_baseline_seconds, :json
  end
end
