# One stay with an FAQ question open (D-094): its key (Faq), the whole seconds it was open, and when. It also carries the
# reader_id (D-095), a random ID the browser made and keeps in localStorage, so people can be counted. It is linked to no
# user, IP address, user agent, cookie or session, so a read can't be traced to a person. Reads from before it have none.
# The page sends it as the question closes.
class FaqRead < ApplicationRecord
  MIN_SECONDS = 1
  # A tab left open doesn't skew the numbers: a longer read counts as ten minutes.
  MAX_SECONDS = 600

  validates :key, inclusion: { in: ->(_) { Faq.keys } }
  # The reader ID is UUID-shaped, as crypto.randomUUID() or the page's fallback makes it.
  READER_ID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  validates :reader_id, format: { with: READER_ID_FORMAT }, length: { maximum: 64 }, allow_nil: true
  validates :seconds, numericality: { only_integer: true, in: MIN_SECONDS..MAX_SECONDS }

  # Keeps one read, or nothing: an unknown key or under a second is dropped, and a long one is cut to MAX_SECONDS.
  # Returns the read, or nil when nothing was kept.
  # A malformed reader_id is left off: the read is kept without it.
  def self.record(key, seconds, reader_id = nil)
    seconds = Integer(seconds.to_s, 10, exception: false)
    return if seconds.nil? || seconds < MIN_SECONDS

    reader_id = reader_id.to_s.downcase
    reader_id = nil unless reader_id.length <= 64 && READER_ID_FORMAT.match?(reader_id)
    read = new(key: key.to_s, seconds: [ seconds, MAX_SECONDS ].min, reader_id:)
    read if read.save
  end
end
