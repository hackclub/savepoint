# D-151: a ban Hackatime caused is logged with no admin behind it.
class AllowAuditEventsWithoutAPerson < ActiveRecord::Migration[8.1]
  def change
    change_column_null :admin_audit_events, :user_id, true
  end
end
