# An admin's personal token for the admin MCP server (D-046). Only the SHA-256 of the token is kept, so the token itself
# is shown once, when it's made. Revoking sets revoked_at.
class CreateAdminTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end
    add_index :admin_tokens, :token_digest, unique: true
  end
end
