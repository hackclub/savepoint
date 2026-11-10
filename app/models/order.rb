# Spending approved hours (Project#hours_to_spend) on a prize in Prize::ALL, like money: one of each, as many as they
# cover, to their address as it is then. It waits until an admin orders it (Admin::OrdersController), and the bot DMs
# them then (OrderNotifier).
class Order < ApplicationRecord
  include AirtableSynced

  # The columns the Airtable copy (AirtableFields.order) reads.
  AIRTABLE_COLUMNS = %w[status hours prize_key ordered_at].freeze

  # A project's hours spent come from its orders.
  after_commit -> { Project.where(id: project_id).update_all(synced_at: nil, updated_at: Time.current) }, on: %i[create update destroy]
  STATUSES = %w[waiting ordered cancelled].freeze

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
  # The free stickers can be claimed up to Reward::STICKER_PACKS_MAX times, once for each pack earned (stickers_earned).
  validates :prize_key, uniqueness: { scope: :project_id, conditions: -> { where.not(status: "cancelled") }, message: "is one you've bought already" }, allow_nil: true, unless: :stickers?
  validate :shop_open, :not_banned, on: :create
  validate :stickers_earned, :covered_by_approved_hours, :addressed, :deliverable, :old_enough, :has_email, on: :create

  # An order that can't go ahead at dispatch (ban, stickers no longer earned, hours no longer covering it). The message
  # is plain words for the admin.
  class Blocked < StandardError; end

  BANNED = "This account can't claim prizes.".freeze

  scope :waiting, -> { where(status: "waiting") }
  scope :ordered, -> { where(status: "ordered") }
  scope :cancelled, -> { where(status: "cancelled") }

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
  # Under the row lock, so two admins pressing at once order it once. Raises Blocked when the owner is banned (D-148).
  def ordered!(by:, theseus_letter_id: nil)
    ordered = with_lock do
      next false unless waiting?

      check_dispatchable!
      update!(status: "ordered", ordered_by: by, ordered_at: Time.current, theseus_letter_id:)
      true
    end
    OrderNotifier.ordered(self) if ordered
    ordered
  end

  def cancelled? = status == "cancelled"

  # Saved and not cancelled: an order that holds its prize and its hours.
  def live? = persisted? && !cancelled?

  # A waiting order is cancelled: the row stays, off the hours spent, so the hours come back. Under the row lock, so two
  # cancels at once cancel it once. Answers false, changing nothing, when it is no longer waiting.
  def cancel!
    with_lock do
      next false unless waiting?

      update!(status: "cancelled")
      true
    end
  end

  # An ordered order goes back to waiting, for when the shop cancelled it after it was marked ordered. It still counts as
  # spent, so the hours stay. When it was ordered, who ordered it and the Theseus letter are cleared. Under the row lock.
  # Answers false, changing nothing, when it is not ordered.
  def reopen!
    with_lock do
      next false unless ordered?

      update!(status: "waiting", ordered_at: nil, ordered_by: nil, theseus_letter_id: nil)
      true
    end
  end

  # A banned person's waiting order is cancelled with the ban (User#ban!, D-148).
  def cancel_for_ban!
    cancel!
  end

  # The free stickers HQ sends through Theseus (D-067).
  def stickers? = prize_key == Prize::STICKERS.key

  # What an admin's "ordered" does, for the Orders page and the MCP tool. Stickers go to Theseus first and are marked
  # ordered only if it took them, so one can't be marked without being sent. Answers :ordered, :sent, :already_sent
  # (Theseus had it, so there's no letter id), or false when it was ordered already. A Theseus failure raises
  # TheseusClient::Error and changes nothing.
  # Raises Order::Blocked, before anything is sent, when the owner is banned or no longer qualifies (D-148). The whole of
  # it runs under the order's row lock, so a second press waits and then finds it done.
  def place!(by:)
    with_lock do
      next false unless waiting?

      check_dispatchable!
      next (ordered!(by:) && :ordered) unless stickers?

      letter_id = begin
        TheseusClient.new.send_stickers(self)
      rescue TheseusClient::AlreadySent
        nil
      end
      next false unless ordered!(by:, theseus_letter_id: letter_id)

      letter_id ? :sent : :already_sent
    end
  end

  private
    # The checks again at dispatch (D-148): the person may have been banned, lost their stickers or their hours since they claimed.
    def check_dispatchable!
      user = project.user
      raise Blocked, "#{user.name.presence || "This person"} is banned. Cancel this order." if user.banned?
      raise Blocked, "Hackatime has banned this account (red trust)." if user.hackatime_banned?
      if stickers?
        raise Blocked, "They haven't earned these stickers." if Reward.sticker_packs_earned(user).zero?
        raise Blocked, "Hack Club stickers aren't available on this account." unless user.sticker_eligible?
      elsif project.hours_approved + project.shop_hours_credit.to_f < project.orders.where.not(id:).where.not(status: "cancelled").sum(:hours).to_f + hours.to_f
        raise Blocked, "Their approved hours no longer cover this prize."
      end
    end

    def not_banned
      user = project&.user
      errors.add(:base, BANNED) if user&.banned? || user&.hackatime_banned?
    end

    # D-148: a posted prize needs a postal code (where the country has one) and a phone. The free stickers go through
    # Theseus, which checks the address itself.
    def deliverable
      return unless prize_item&.physical? && !stickers?

      problem = ShippingAddress.from_hash(address).delivery_problems.values.first
      errors.add(:base, problem) if problem
    end

    # D-148: a prize whose terms say 18 or older needs a birthdate that shows it.
    def old_enough
      return unless prize_item&.adults_only?

      born = (Date.parse(project.user.birthdate.to_s) rescue nil)
      if born.nil? then errors.add(:base, "We need your birthdate to check you're 18 or older for this prize.")
      elsif born > 18.years.ago.to_date then errors.add(:base, "You need to be 18 or older to claim this prize.")
      end
    end

    # A code sent by email needs somewhere to send it.
    def has_email
      errors.add(:base, "We need an email to send it to.") if prize_item&.digital? && project&.user&.email.blank?
    end

    # D-138: claiming ends when the shop closes (Program::SHOP_CLOSES_AT), a week after hours and shipping.
    def shop_open
      errors.add(:base, "The shop is closed.") unless project ? project.shop_open? : Program.shop_open?
    end

    # A prize's hours, and where it goes, as they are now.
    def price_and_route
      return unless project && prize_item

      self.hours = prize_item.hours
      self.address ||= address_with_phone(project.user)
      self.recipient_name ||= project.user.recipient_name
    end

    # Their Hack Club address with the phone Hack Club Auth shared, for an order made without the claim step's form.
    def address_with_phone(user)
      return if user.address.blank?

      ShippingAddress.from_hash(user.address).tap { it.phone_number ||= user.phone_number }.to_h
    end

    # The free stickers (D-051) are for someone who earned them: a sticker Reward for each pack, the first-hour one or a
    # comeback one (D-078). They cost no hours. The packs are counted afresh and the order is saved under the project's lock
    # (see #save), so two claims at once can't take more packs than they earned or than Reward::STICKER_PACKS_MAX.
    def stickers_earned
      return unless stickers? && project

      user = project.user
      claimed = project.orders.where(prize_key: Prize::STICKERS.key).where.not(id:).where.not(status: "cancelled").count
      earned = Reward.sticker_packs_earned(user)
      if earned.zero? then errors.add(:prize_key, "isn't one you've earned")
      elsif claimed >= [ earned, Reward::STICKER_PACKS_MAX ].min then errors.add(:prize_key, "is one you've bought already")
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
