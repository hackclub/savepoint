# D-157: hours an admin credits to one project's shop balance. Never a ship, its approved hours, or anything sent to Unified.
class AddShopHoursCreditToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :shop_hours_credit, :decimal, precision: 6, scale: 2, default: 0, null: false
    add_column :projects, :shop_hours_credit_reason, :text
    add_column :projects, :shop_hours_credit_by_id, :bigint
  end
end
