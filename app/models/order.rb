# Spending approved hours (Project#hours_to_spend) on a prize in Prize::ALL, like money: one of each, as many as they
# cover, to their address as it is then. It waits until an admin orders it (Admin::OrdersController), and the bot DMs
# them then (OrderNotifier).
class Order < ApplicationRecord
  include AirtableSynced

  # The columns the Airtable copy (AirtableFields.order) reads.
  AIRTABLE_COLUMNS = %w[status hours prize_key ordered_at].freeze

  # A project's hours spent come from its orders.
  after_commit -> { Project.where(id: project_id).update_all(synced_at: nil, updated_at: Time.current) }, on: %i[create update destroy]
  STATUSES = %w[waiting ordered].freeze

  belongs_to :project
  belongs_to :ordered_by, class_name: "User", optional: true

  # Where to post it, as they confirmed it when they bought it (ShippingAddress, D-024).
  serialize :address, coder: JSON
  encrypts :address
  # Who it's for, as they asked when they bought it (User#recipient_name): their preferred name, or their Hack Club one.
  encrypts :recipient_name

  before_validation :price_and_route, on: :create

  validates :status, inclusion: { in: STATUSES }
  validates :prize_key, inclusion: { in: Prize::CLAIMABLE.map(&:key) }
  validates :prize_key, uniqueness: { scope: :project_id, message: "is one you've bought already" }, allow_nil: true
  validate :stickers_earned, :covered_by_approved_hours, :addressed, on: :create

  scope :waiting, -> { where(status: "waiting") }
  scope :ordered, -> { where(status: "ordered") }

  # Claiming is a check then an insert (covered_by_approved_hours, then the row), so a new order is saved under its project's
  # row lock: parallel claims for different prizes take turns, and each one checks the hours the last one left. The lock
  # reloads the project, so hours_to_spend reads the orders as they are now. Every way of making an order goes through
  # these two.
  def save(**)
    return super unless new_record? && project

    project.with_lock { super }
  end

  def save!(**)
    return super unless new_record? && project

    project.with_lock { super }
  end

  def waiting? = status == "waiting"
  def ordered? = status == "ordered"

  # The prize it's for, from Prize::CLAIMABLE (Prize::ALL, and the free stickers).
  def prize_item = (Prize.find(prize_key) if prize_key)

  # "Aseprite"
  def configuration = prize_item.name

  # Why it can't be bought, as the bot says it.
  def problem
    error = errors.first
    return error&.message unless error&.attribute == :prize_key

    "#{prize_item&.name || "That"} #{error.message}"
  end

  # An admin's ordered it: once.
  def ordered!(by:, theseus_letter_id: nil)
    return false unless waiting?

    update!(status: "ordered", ordered_by: by, ordered_at: Time.current, theseus_letter_id:)
    OrderNotifier.ordered(self)
    true
  end

  # The free stickers HQ sends through Theseus (D-067).
  def stickers? = prize_key == Prize::STICKERS.key

  # What an admin's "ordered" does, for the Orders page and the MCP tool. Stickers go to Theseus first and are marked
  # ordered only if it took them, so one can't be marked without being sent. Answers :ordered, :sent, :already_sent
  # (Theseus had it, so there's no letter id), or false when it was ordered already. A Theseus failure raises
  # TheseusClient::Error and changes nothing.
  def place!(by:)
    return false unless waiting?
    return (ordered!(by:) && :ordered) unless stickers?

    letter_id = begin
      TheseusClient.new.send_stickers(self)
    rescue TheseusClient::AlreadySent
      nil
    end
    return false unless ordered!(by:, theseus_letter_id: letter_id)

    letter_id ? :sent : :already_sent
  end

  private
    # A prize's hours, and where it goes, as they are now.
    def price_and_route
      return unless project && prize_item

      self.hours = prize_item.hours
      self.address ||= project.user.address
      self.recipient_name ||= project.user.recipient_name
    end

    # The free stickers (D-051) are for someone who earned them: the "stickers" Reward. They cost no hours.
    def stickers_earned
      return unless prize_key == "stickers" && project

      user = project.user
      if !user.earned?("stickers") then errors.add(:prize_key, "isn't one you've earned")
      elsif !user.sticker_eligible? then errors.add(:base, "Hack Club stickers aren't available on this account")
      end
    end

    def covered_by_approved_hours
      return unless project && hours && errors.empty?

      left = project.hours_to_spend
      errors.add(:base, "That's #{hours.to_f.round(1).to_s.delete_suffix(".0")} hours, and you've #{left.round(1).to_s.delete_suffix(".0")} approved to spend.") if hours > left
    end

    # The claim step checks each field and says which (OrdersController). This is the backstop for any other way in.
    def addressed
      errors.add(:base, "We need an address to post it.") unless ShippingAddress.from_hash(address).valid?
    end
end
