# Save Point's projects pick a prize from Prize::ALL (prize_key) and say whether the game was a jame gam entry. The
# old console columns (prize, prize_color, prize_options) stay for projects that already have them, and prize may now
# be empty.
class AddPrizeKeyAndJameGamToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :prize_key, :string
    add_column :projects, :jame_gam, :boolean, default: false, null: false
    change_column_null :projects, :prize, true
  end
end
