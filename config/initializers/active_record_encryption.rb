# Active Record encryption, for secrets we keep (like Hackatime access tokens). The keys come from the environment
# when set, and otherwise are derived from secret_key_base, so every environment has them without adding any.
key = ->(name) { Rails.application.key_generator.generate_key("active_record_encryption/#{name}", 32).unpack1("H*") }

ActiveRecord::Encryption.configure(
  primary_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") { key.("primary_key") },
  deterministic_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") { key.("deterministic_key") },
  key_derivation_salt: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") { key.("key_derivation_salt") }
)
