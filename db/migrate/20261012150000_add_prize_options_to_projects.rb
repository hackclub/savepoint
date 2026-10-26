# The extras you picked for your console in the shop (Console#options): option id => choice id. Empty means the
# defaults.
class AddPrizeOptionsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :prize_options, :json, default: {}, null: false
  end
end
