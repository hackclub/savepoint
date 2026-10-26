# Blazer is gone (D-038). Its saved queries, dashboards, checks and audit log go with it.
class DropBlazerTables < ActiveRecord::Migration[8.1]
  def up
    %i[blazer_checks blazer_dashboard_queries blazer_dashboards blazer_audits blazer_queries].each do |table|
      drop_table table, if_exists: true
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Blazer's saved queries were dropped for good (D-038)."
  end
end
