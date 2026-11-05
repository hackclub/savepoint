# Someone signed in with Hack Club Auth. hca_id is their HCA subject (ident!…); everything else is copied
# from HCA's claims each time they sign in, so it stays current.
class User < ApplicationRecord
  include Streakable
  include AirtableSynced

  # The columns the Airtable copy (AirtableFields.user) reads.
  AIRTABLE_COLUMNS = %w[email name first_name last_name slack_id hca_id hackatime_uid verification_status ysws_eligible banned_at].freeze
  # A submission row carries these too, and approved ships are copied only when marked, so they mark the user's ships.
  AIRTABLE_SHIP_COLUMNS = %w[email name first_name last_name slack_display_name slack_username hackatime_uid address birthdate banned_at].freeze
  after_update -> { Ship.approved.where(project_id: Project.where(user_id: id)).update_all(synced_at: nil, updated_at: Time.current) },
               if: -> { (saved_changes.keys & AIRTABLE_SHIP_COLUMNS).any? }
  # Gate audit finding 15: a ship the Unified YSWS DB already took cannot be sent again, so a change to its person is marked for the admins.
  after_update -> { Ship.approved.where(in_unified: true, project_id: Project.where(user_id: id)).update_all(changed_after_unified_at: Time.current) },
               if: -> { (saved_changes.keys & AIRTABLE_SHIP_COLUMNS).any? }

  has_one :project, dependent: :destroy
  has_many :nudges, dependent: :destroy
  has_many :admin_tokens, dependent: :destroy

  # Linking Hackatime gives us their Hackatime ID and a token that reads their projects and hours.
  encrypts :hackatime_access_token
  # D-147: Hack Club Auth's tokens from sign-in, for asking its /me (see #confirm_ysws_eligibility!).
  encrypts :hca_access_token, :hca_refresh_token
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
  # request (ApplicationController#end_banned_session), the app sends it no Slack DM bar the ban's own (D-137: SlackBot,
  # SlackMessageJob, Nudge::Context#reachable?, Nudge::Banned) and it's off the leaderboard (Leaderboard.ranked).
  # D-137: the one DM a banned account gets, saying so (Nudge::Banned), queued once the ban has committed.
  after_update_commit -> { Nudge::Banned.queue(self) }, if: -> { saved_change_to_banned_at?(from: nil) }

  scope :banned, -> { where.not(banned_at: nil) }

  def banned? = banned_at.present?

  def ban!(reason, by:)
    with_lock do
      update!(banned_at: Time.current, ban_reason: reason)
      # D-148: the prizes they were waiting for are cancelled, so nothing is posted to a banned account.
      project&.orders&.waiting&.find_each(&:cancel_for_ban!)
      project&.ships&.pending&.find_each do |ship|
        rejection = { status: "rejected", fraud_status: "banned", fraud_reviewer: by, fraud_reviewed_at: Time.current,
                      fraud_notes: "Banned with the account: #{reason}", decided_by: by, decided_at: Time.current }
        # D-112: a ship that waits for its fraud check holds the message written under Approve, which isn't the ban's.
        rejection[:review_feedback] = Ship::BAN_NOTE if ship.awaiting_fraud?
        ship.update!(rejection)
      end
    end
  end

  # D-148: an admin lifts a ban, with a reason. The ban's own reason stays beside it, and the orders the ban cancelled
  # wait again. False unless banned or the reason is blank. The ship the ban rejected stays rejected.
  def lift_ban!(reason, by:)
    reason = reason.to_s.strip
    return false if reason.empty?

    with_lock do
      next false unless banned?

      update!(banned_at: nil, ban_reason: "Lifted by #{by.name.presence || by.public_name} on #{Time.current.to_date}: #{reason}. Banned for: #{ban_reason}")
      project&.orders&.cancelled&.find_each { it.update!(status: "waiting") }
      true
    end
  end

  # Hackatime's trust level is red: banned. Stored from the stats answers (Hackatime.refresh_trust_level!); unknown is not banned.
  def hackatime_banned? = hackatime_trust_level == "red"

  # Whether the free stickers (D-051) are for them: Hack Club Auth calls them YSWS-eligible, and Hackatime hasn't banned them.
  def sticker_eligible? = ysws_eligible? && !hackatime_banned?

  # Your timezone (IANA, like "America/New_York"), from your browser whenever it says something different, so it
  # follows you when you travel. Anything that isn't a real timezone is ignored.
  def remember_timezone(name)
    name = TZInfo::Timezone.get(UserTimezone::LEGACY.fetch(name.to_s, name.to_s)).identifier
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
    UserTimezone.zone(timezone)
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
    listed_admin? || (Rails.env.development? && ENV["DEV_ADMIN_FOR_ALL"] == "1")
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
    # An all-digit query also matches a Hackatime user ID exactly.
    where("name ILIKE :q OR email ILIKE :q OR slack_display_name ILIKE :q OR slack_id ILIKE :q OR hca_id ILIKE :q OR hackatime_uid = :uid",
          q: pattern, uid: (query.to_s if query.to_s.match?(/\A\d+\z/)))
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
        # D-143: Hack Club Auth's family_name (profile scope), kept at every sign-in. Kept if one doesn't share it.
        last_name: auth.info.last_name.presence || user.last_name,
        slack_id: claims[:slack_id],
        verification_status: claims[:verification_status],
        ysws_eligible: claims[:ysws_eligible] || false,
        # Kept if this sign-in didn't share one (from before the scope, or a community-app sign-in).
        address: address_from(claims[:address]) || user.address,
        phone_number: claims[:phone_number].presence || user.phone_number,
        birthdate: claims[:birthdate].presence || user.birthdate,
        # D-147: kept for /me. Kept as they were if this sign-in didn't carry one.
        hca_access_token: auth.credentials&.token.presence || user.hca_access_token,
        hca_refresh_token: auth.credentials&.refresh_token.presence || user.hca_refresh_token
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

  # D-147: whether they are YSWS eligible in Hack Club Auth right now. It asks /me and stores the answer; when HCA can't be asked
  # (no token kept yet, or it is down), the value stored at sign-in stands. A person who turns eligible has their approved ships
  # sent to Airtable again, because the Unified YSWS box waits for it.
  def confirm_ysws_eligibility!
    identity = HackClubAuth.identity(self)
    was = ysws_eligible?
    update!(ysws_eligible: identity["ysws_eligible"] == true, verification_status: identity["verification_status"].presence || verification_status)
    Ship.approved.where(project_id: Project.where(user_id: id), in_unified: false).update_all(synced_at: nil, airtable_failed_at: nil) if ysws_eligible? && !was
    ysws_eligible?
  rescue HackClubAuth::Unavailable => error
    Rails.logger.warn("[hca] eligibility not refreshed for user #{id}: #{error.message}")
    ysws_eligible?
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
