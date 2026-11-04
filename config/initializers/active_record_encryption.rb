# Active Record encryption, for secrets we keep (like Hackatime access tokens). The keys come from the environment
# when set, and otherwise are derived from secret_key_base, so every environment has them without adding any.
key = ->(name) { Rails.application.key_generator.generate_key("active_record_encryption/#{name}", 32).unpack1("H*") }

ActiveRecord::Encryption.configure(
  primary_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") { key.("primary_key") },
  deterministic_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") { key.("deterministic_key") },
  key_derivation_salt: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") { key.("key_derivation_salt") }
)

# Without the three variables the keys come from secret_key_base, so that one secret unlocks sessions and every encrypted column
# and cannot rotate. Production says so at boot. REQUIRE_AR_ENCRYPTION_KEYS=1 makes the missing variables stop the boot. It is off
# until Orchard is known to hold all three, because the default would take the site down if they are not set.
if Rails.env.production?
  missing = %w[ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT].select { ENV[it].blank? }
  if missing.any?
    message = "Active Record encryption keys come from secret_key_base because #{missing.to_sentence} #{missing.one? ? 'is' : 'are'} not set"
    raise message if ENV["REQUIRE_AR_ENCRYPTION_KEYS"] == "1"

    Rails.logger.warn(message)
  end
end
