# Hackatime's trust level for someone (blue, green, yellow, red), read from the stats answer. Red is banned (D-051).
class AddHackatimeTrustLevelToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :hackatime_trust_level, :string
  end
end
