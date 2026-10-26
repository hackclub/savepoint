# Viewing as a participant is logged as an audit event too, and it has no admin token: it happens on the web.
class AllowAuditEventsWithoutAToken < ActiveRecord::Migration[8.1]
  def change
    change_column_null :admin_audit_events, :admin_token_id, true
  end
end
