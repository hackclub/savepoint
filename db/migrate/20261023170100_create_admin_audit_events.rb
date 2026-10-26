# One row per admin MCP tool call (D-046), written before the tool runs: who, with which token, which tool, and the IDs
# the arguments name. Never any text a participant wrote, an email, or a token.
class CreateAdminAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audit_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :admin_token, null: false, foreign_key: true
      t.string :tool, null: false
      t.jsonb :ids, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :admin_audit_events, :created_at
  end
end
