# Who is working on a ship in one admin stage ("review" or "fraud"), so two admins don't judge the same one. A claim
# goes stale 90 seconds after its last heartbeat, and then anyone may take it (playground's Claim). The review page
# beats every 30 seconds (the heartbeat Stimulus controller) while it is open.
class Claim < ApplicationRecord
  STALE_AFTER = 90.seconds
  STAGES = %w[review fraud].freeze

  belongs_to :ship
  belongs_to :user

  validates :stage, inclusion: { in: STAGES }

  scope :live, -> { where(heartbeat_at: STALE_AFTER.ago..) }

  def live? = heartbeat_at > STALE_AFTER.ago

  # [claim, took_it]. A live claim someone else holds is left alone unless force is true (take over).
  def self.acquire(ship, stage, user, force: false)
    claim = find_or_initialize_by(ship:, stage:)
    return [ claim, false ] if claim.persisted? && claim.user_id != user.id && claim.live? && !force

    claim.update!(user:, heartbeat_at: Time.current)
    [ claim, true ]
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.held_by_other?(ship, stage, user)
    live.where(ship:, stage:).where.not(user:).exists?
  end
end
