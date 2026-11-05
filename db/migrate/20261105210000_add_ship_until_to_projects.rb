# D-155: a deadline an admin sets for one project, so a person gets a private window to ship after the public end.
class AddShipUntilToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :ship_until, :datetime
  end
end
