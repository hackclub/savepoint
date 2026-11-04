# D-147: Hack Club Auth's tokens, kept at sign-in (encrypted) so the app can ask HCA's /me for the person's eligibility at a claim
# and at the Unified YSWS submit. Additive only. Someone who signed in before this has none until their next sign-in, and until
# then the stored ysws_eligible stands.
class AddHcaTokensToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :hca_access_token, :text
    add_column :users, :hca_refresh_token, :text
  end
end
