# D-091: a hand-picked Hackatime link needs no confirmation, so the time D-087 held on doubtful ones counts. Only an
# unconfirmed auto-link keeps its time held. Safe to run again: it moves only what is still held.
class ReleaseTimeHeldOnHandPickedLinks < ActiveRecord::Migration[8.1]
  def up
    released = StreakActivity.release_held_on_hand_picked_links!
    say "released held time for #{released.size} people: user ids #{released.join(", ")}"
  end

  def down; end
end
