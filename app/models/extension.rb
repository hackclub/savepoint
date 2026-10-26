# Asking for Program::EXTENSION_DAYS more days to ship: one per project, with why, waiting until an admin approves
# or denies it (Admin::ExtensionsController). Approved, the project's deadline moves (Project#deadline). Either way
# The bot DMs them (ExtensionNotifier).
class Extension < ApplicationRecord
  STATUSES = %w[pending approved denied].freeze
  DECISIONS = %w[approved denied].freeze
  REASON_MAX = 500

  belongs_to :project
  belongs_to :decided_by, class_name: "User", optional: true

  normalizes :reason, with: ->(reason) { reason.strip }

  validates :status, inclusion: { in: STATUSES }
  validates :reason, presence: { message: "is needed: a line on why" }, length: { maximum: REASON_MAX }
  validates :project_id, uniqueness: { message: "has asked already" }

  scope :pending, -> { where(status: "pending") }
  scope :decided, -> { where.not(status: "pending") }

  def pending? = status == "pending"
  def approved? = status == "approved"
  def denied? = status == "denied"

  # An admin's call, made once: false if it's been made already (or isn't a decision).
  def decide!(decision, by:)
    return false unless pending? && DECISIONS.include?(decision)

    update!(status: decision, decided_by: by, decided_at: Time.current)
    ExtensionNotifier.decided(self)
    true
  end
end
