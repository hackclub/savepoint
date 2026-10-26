class AddApprovedHoursToShips < ActiveRecord::Migration[8.1]
  def change
    # The hours an admin approved with the ship: what it took (hours) unless they lowered it. What the shop spends.
    add_column :ships, :approved_hours, :decimal, precision: 6, scale: 2
  end
end
