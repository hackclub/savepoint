# D-158: a later shop close an admin sets for one project. Everyone else's shop still closes at Program::SHOP_CLOSES_AT.
class AddShopUntilToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :shop_until, :datetime
    add_column :projects, :shop_until_reason, :text
  end
end
