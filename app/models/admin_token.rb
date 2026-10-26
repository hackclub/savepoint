# An admin's personal token for the admin MCP server (D-046, AdminMcp). The token is `spat_` and 32 random bytes,
# shown once; only its SHA-256 is kept. It works only while it isn't revoked and its owner is still an admin.
class AdminToken < ApplicationRecord
  PREFIX = "spat_"
  # The prefix and 32 bytes in base64url (43 characters).
  PATTERN = /\A#{PREFIX}[A-Za-z0-9_-]{43}\z/
  NAME_MAX = 60

  belongs_to :user
  has_many :audit_events, class_name: "AdminAuditEvent", dependent: :destroy

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: { message: "is needed: what the token is for" }, length: { maximum: NAME_MAX }
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  # Makes a token for `user` and returns it with its record. The token text is never stored, so this is the only time
  # it can be read.
  def self.generate!(user:, name:)
    token = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    [ token, create!(user:, name:, token_digest: digest(token)) ]
  end

  # The unrevoked token with this text, or nil. Whether its owner's still an admin is the caller's to check.
  def self.authenticate(token)
    return unless token.to_s.match?(PATTERN)

    active.includes(:user).find_by(token_digest: digest(token))
  end

  def revoked? = revoked_at.present?

  def revoke! = (update!(revoked_at: Time.current) unless revoked?)

  # Noted at most once a minute, so a busy session doesn't write on every call.
  def used!
    touch(:last_used_at) if last_used_at.nil? || last_used_at < 1.minute.ago
  end
end
