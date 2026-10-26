# Which colour of your console you picked in the shop (Console#colors). Nothing means the first one it comes in.
class AddPrizeColorToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :prize_color, :string
  end
end
