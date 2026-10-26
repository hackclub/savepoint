# One answer to the NPS form: how likely a participant is to recommend Save Point to a friend, from 0 to 10, and what
# they wrote. A participant with no answer from the last 12 hours is due: a ship needs an answer, and once they have
# some Hackatime time the project page asks by itself. There is no reward for one. NpsStats turns the answers into
# the admin's NPS.
class NpsResponse < ApplicationRecord
  belongs_to :user
  belongs_to :project, optional: true

  SCORES = 0..10
  # NPS's three groups by score. NPS is the share of promoters minus the share of detractors.
  PROMOTERS = 9..10
  PASSIVES = 7..8
  DETRACTORS = 0..6
  # Where an answer came from: the popup on the project page (or the link to the form), or a ship.
  SOURCES = %w[daily ship].freeze
  # How often the site asks. An answer spares the participant for this long, and a skipped popup stays shut as long
  # (nps_popup_controller.js).
  INTERVAL = 12.hours
  # Some Hackatime time before the popup opens by itself: as much as a minute.
  ASK_AFTER_SECONDS = 60

  # The questions after the score, in order, and whether each needs an answer. The form, its submit button, and the
  # validations all read this.
  QUESTIONS = {
    doing_well: { label: "What are we doing well?", required: true },
    improve: { label: "What's something we can improve?", required: true },
    anything_else: { label: "Anything else you want to tell us?", required: false }
  }.freeze
  FIELDS = [ :score, *QUESTIONS.keys ].freeze
  MAX_LENGTH = 5000

  validates :score, numericality: { only_integer: true, in: SCORES }
  validates :source, inclusion: { in: SOURCES }
  validates :project, presence: true, if: -> { source == "ship" }
  validates(*QUESTIONS.select { |_, question| question[:required] }.keys, presence: true)
  validates(*QUESTIONS.keys, length: { maximum: MAX_LENGTH })

  # Tests of anything but the NPS turn the asking off (test_helper.rb), so the popup never opens and a ship needs
  # no answer.
  class << self
    attr_writer :asking
    def asking = @asking.nil? ? true : @asking
  end

  # Who answers: a signed-in participant. Someone on the list of admins is never asked (not "admin?", which is true
  # for everyone in development).
  def self.participant?(user) = user.present? && !user.listed_admin?
  def self.asks?(user) = asking && participant?(user)

  def self.answered_within?(user, interval = INTERVAL, now: Time.current) = where(user:, created_at: (now - interval)..).exists?

  # A participant the site asks, with no answer in the last 12 hours. A ship needs an answer from them.
  def self.due?(user, now: Time.current) = asks?(user) && !answered_within?(user, now:)

  # The project page opens the form by itself only for a due participant with some Hackatime time on a project.
  def self.ask?(user, now: Time.current)
    due?(user, now:) && user.streak_activities.sum(:coded_seconds) >= ASK_AFTER_SECONDS
  end

  # The day a time falls in, as the admin numbers count days (UTC).
  def self.day(time = Time.current) = time.utc.to_date
end
