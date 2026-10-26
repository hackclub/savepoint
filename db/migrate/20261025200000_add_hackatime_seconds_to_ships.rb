# D-063: the seconds on each linked Hackatime project from Save Point's start to the ship ({ "name" => seconds }), kept
# when the ship is made so the review can set them beside the live figures. Null on ships from before this existed.
class AddHackatimeSecondsToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :hackatime_seconds, :json
  end
end
