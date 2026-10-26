# D-085: the reviewer says how many of a ship's Lapse hours were coding. lapse_seconds is the "timelapsing" part of art_seconds,
# kept apart so the split can't pass it. lapse_coding_hours is the reviewer's figure, 0 (all art) until they set it.
class AddLapseSplitToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :lapse_seconds, :integer
    add_column :ships, :lapse_coding_hours, :decimal, precision: 6, scale: 2, default: 0, null: false
  end
end
