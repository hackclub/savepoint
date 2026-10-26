# One time a ship that waited for its fraud check went back to review: who sent it, why, and the review that was
# cleared. The review page lists these and refills its form from the last (D-063).
class ShipSendBack < ApplicationRecord
  belongs_to :ship
  belongs_to :user

  validates :reason, presence: true
end
