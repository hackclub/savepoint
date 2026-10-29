# Someone signed in with Hack Club Auth. hca_id is their HCA subject (ident!…); everything else is copied
# from HCA's claims each time they sign in, so it stays current.
class User < ApplicationRecord
  include Streakable
  include AirtableSynced

  # The columns the Airtable copy (AirtableFields.user) reads.
  AIRTABLE_COLUMNS = %w[email name first_name slack_id hca_id hackatime_uid verification_status ysws_eligible].freeze
  # A submission row carries these too, and approved ships are copied only when marked, so they mark the user's ships.
  AIRTABLE_SHIP_COLUMNS = %w[email name first_name hackatime_uid address birthdate].freeze
  after_update -> { Ship.approved.where(project_id: Project.where(user_id: id)).update_all(synced_at: nil, updated_at: Time.current) },
               if: -> { (saved_changes.keys & AIRTABLE_SHIP_COLUMNS).any? }

  has_one :project, dependent: :destroy
  has_many :nudges, dependent: :destroy
  has_many :admin_tokens, dependent: :destroy

  # Linking Hackatime gives us their Hackatime ID and a token that reads their projects and hours.
  encrypts :hackatime_access_token
  # Where to post things, from Hack Club Auth (its address claim): street_address, locality, region, postal_code and
  # country. Encrypted, and only for sending prizes and a ship's submission.
  ADDRESS_FIELDS = %w[street_address locality region postal_code country].freeze
  serialize :address, coder: JSON
  encrypts :address
  # And their phone and birthdate ("2010-04-01"), from the phone and birthdate scopes, for a ship's submission.
  encrypts :phone_number, :birthdate
  # The name they'd like on a parcel in place of the one from Hack Club Auth (optional; see #recipient_name).
  encrypts :preferred_name
  normalizes :preferred_name, with: ->(name) { name.to_s.gsub(/[[:cntrl:]]/, " ").squeeze(" ").strip.presence }
  validates :preferred_name, length: { maximum: 120 }

  validates :hca_id, presence: true, uniqueness: true
  validates :hackatime_uid, uniqueness: { message: "is already linked to someone else here" }, allow_nil: true

  # Streak days run 2am to 2am local, so they're counted again in the new timezone.
  after_update_commit :refresh_streak!, if: -> { saved_change_to_timezone? && project&.tracking? }

  # Your picture is your Slack one (slack_avatar_url). Without one, it's the first letter of your public name on a
  # colour, picked from your Hack Club ID so it's always the same one.
  AVATAR_COLORS = %w[#ec3750 #1a73e8 #1e7b45 #b06000 #8430ce #00796b #c62828 #3949ab #e8710a #d01884 #0b8043 #5f6368].freeze

  # What everyone else sees you as (D-012): your Slack display name, then your Slack username, then a player
  # number ("Player 42", from your Hack Club ID, so it never changes) if you have no Slack profile. Your real name is never shown to anyone but you (and admins).
  def public_name
    slack_display_name.presence || slack_username.presence || "Player #{avatar_seed % 10_000}"
  end

  # Who a parcel is for: the name they asked for, or else the one from Hack Club Auth.
  def recipient_name
    preferred_name.presence || name
  end

  def avatar_color
    AVATAR_COLORS[avatar_seed % AVATAR_COLORS.size]
  end

  def hackatime_linked?
    hackatime_uid.present? && hackatime_access_token.present?
  end

  # D-063: banned by an admin after a fraud verdict (Ship#ban_for_fraud!). A banned account can't sign in, ship or claim
  # a prize, and its other ships still waiting for a verdict are rejected. D-113: its open sessions end on the next
  # request (ApplicationController#end_banned_session), the app sends it no Slack DM (SlackBot, SlackMessageJob,
  # Nudge::Context#reachable?) and it's off the leaderboard (Leaderboard.ranked). Nobody is told.
  scope :banned, -> { where.not(banned_at: nil) }

  def banned? = banned_at.present?

  def ban!(reason, by:)
    transaction do
      update!(banned_at: Time.current, ban_reason: reason)
      project&.ships&.pending&.find_each do |ship|
        rejection = { status: "rejected", fraud_status: "banned", fraud_reviewer: by, fraud_reviewed_at: Time.current,
                      fraud_notes: "Banned with the account: #{reason}", decided_by: by, decided_at: Time.current }
        # D-112: a ship that waits for its fraud check holds the message written under Approve, which isn't the ban's.
        rejection[:review_feedback] = Ship::BAN_NOTE if ship.awaiting_fraud?
        ship.update!(rejection)
      end
    end
  end

  # Hackatime's trust level is red: banned. Stored from the stats answers (Hackatime.refresh_trust_level!); unknown is not banned.
  def hackatime_banned? = hackatime_trust_level == "red"

  # Whether the free stickers (D-051) are for them: Hack Club Auth calls them YSWS-eligible, and Hackatime hasn't banned them.
  def sticker_eligible? = ysws_eligible? && !hackatime_banned?

  # Your timezone (IANA, like "America/New_York"), from your browser whenever it says something different, so it
  # follows you when you travel. Anything that isn't a real timezone is ignored.
  def remember_timezone(name)
    name = TZInfo::Timezone.get(name.to_s).identifier
    update!(timezone: name) unless timezone == name
  rescue TZInfo::InvalidTimezoneIdentifier
    nil
  end

  # Where and when you were last seen on the site (D-047), written at most once a minute. It skips callbacks and
  # updated_at, since a page view isn't an edit. The same throttle gates the day's SiteDay (D-076), so it costs one
  # insert a minute at most, and a no-op after the first of the day.
  def touch_last_seen(path, now = Time.current)
    return if last_seen_at && last_seen_at > now - 1.minute

    update_columns(last_seen_at: now, last_seen_path: path)
    SiteDay.record!(self, now)
  end

  # Where you are, for anything that goes by your calendar day (the deadline): your browser's timezone, or UTC until
  # it's said.
  def time_zone
    ActiveSupport::TimeZone[timezone.presence || "UTC"]
  end

  def local_date(now = Time.current)
    now.in_time_zone(time_zone).to_date
  end

  # "stop these messages" in one of the bot's DMs (that nudge counts against what it said), and changing your mind.
  def mute_slack!(nudge)
    transaction do
      update!(slack_muted_at: Time.current) unless slack_muted_at
      nudge.update!(opted_out_at: Time.current) unless nudge.opted_out_at
    end
  end

  def unmute_slack!(nudge)
    transaction do
      update!(slack_muted_at: nil)
      nudge.update!(opted_out_at: nil)
    end
  end

  # The bot DMed you just now (or is about to: a queued one notes it as it's queued, so a cheer queued the same moment
  # waits for it). Everything he sends keeps this, so his messages are spaced out (Nudge::MESSAGE_GAP).
  def slack_dmed!(at = Time.current)
    update_column(:slack_dmed_at, at) if slack_dmed_at.nil? || at > slack_dmed_at
  end

  # Everyone but the admins on the list (listed_admin?), for numbers that should only count participants.
  def self.participants
    where(slack_id: nil).or(where.not(slack_id: Rails.configuration.x.admin_slack_ids))
  end

  # How many people have signed up, for the landing page's live counter. Cached briefly so polling stays cheap.
  def self.participant_count
    Rails.cache.fetch("signups/count", expires_in: 15.seconds) { participants.count }
  end

  def admin?
    Rails.env.development? || listed_admin?
  end

  # On the list of admins (config/initializers), rather than an admin because it's development.
  def listed_admin?
    slack_id.present? && Rails.configuration.x.admin_slack_ids.include?(slack_id)
  end

  # Whether an admin can see the site as you (Admin::ImpersonationsController): not themselves, not another admin.
  def impersonable_by?(admin)
    admin.present? && admin != self && !listed_admin?
  end

  # Name, email, Slack (display name or ID) or Hack Club ID, any part of it, for the admin's list of users.
  def self.search(query)
    pattern = "%#{sanitize_sql_like(query)}%"
    where("name ILIKE :q OR email ILIKE :q OR slack_display_name ILIKE :q OR slack_id ILIKE :q OR hca_id ILIKE :q", q: pattern)
  end

  # A new user also gets the UTM tags their browser first saw (D-043); someone who's signed in before keeps theirs.
  def self.from_omniauth(auth, utm: {})
    claims = auth.extra.raw_info.to_h.with_indifferent_access
    find_or_initialize_by(hca_id: auth.uid).tap do |user|
      user.assign_attributes(utm.slice(*Visit::TAGS)) if user.new_record?
      user.update!(
        email: auth.info.email,
        name: auth.info.name,
        first_name: auth.info.first_name,
        slack_id: claims[:slack_id],
        verification_status: claims[:verification_status],
        ysws_eligible: claims[:ysws_eligible] || false,
        # Kept if this sign-in didn't share one (from before the scope, or a community-app sign-in).
        address: address_from(claims[:address]) || user.address,
        phone_number: claims[:phone_number].presence || user.phone_number,
        birthdate: claims[:birthdate].presence || user.birthdate
      )
    end
  end

  # The address claim as we keep it: its fields, as strings, blanks dropped. Nil if there's nothing to it.
  def self.address_from(claim)
    claim = JSON.parse(claim) if claim.is_a?(String)
    claim.to_h.stringify_keys.slice(*ADDRESS_FIELDS).transform_values { |value| value.to_s.strip }.compact_blank.presence
  rescue JSON::ParserError
    nil
  end

  # We don't have their address (they signed in before we asked, or didn't share it): shipping and buying wait for it.
  def needs_address?
    address.blank?
  end

  # Their address, a line each: "1 Hack Ln\nShelburne, VT 05482\nUS".
  def address_lines(fields = address)
    return if fields.blank?

    [ fields["street_address"], fields["street_address_2"], [ fields["locality"], [ fields["region"], fields["postal_code"] ].compact_blank.join(" ") ].compact_blank.join(", "),
      fields["country"] ].compact_blank.join("\n")
  end

  private
    def avatar_seed
      @avatar_seed ||= Digest::SHA256.hexdigest(hca_id.to_s).first(12).to_i(16)
    end
end
