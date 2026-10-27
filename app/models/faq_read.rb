# One stay with an FAQ question open (D-094): its key (Faq), the whole seconds it was open, and when. No user, IP address,
# user agent or session is kept, so a read can't be traced to a person. The page sends it as the question closes.
class FaqRead < ApplicationRecord
  MIN_SECONDS = 1
  # A tab left open doesn't skew the numbers: a longer read counts as ten minutes.
  MAX_SECONDS = 600

  validates :key, inclusion: { in: ->(_) { Faq.keys } }
  validates :seconds, numericality: { only_integer: true, in: MIN_SECONDS..MAX_SECONDS }

  # Keeps one read, or nothing: an unknown key or under a second is dropped, and a long one is cut to MAX_SECONDS.
  # Returns the read, or nil when nothing was kept.
  def self.record(key, seconds)
    seconds = Integer(seconds.to_s, 10, exception: false)
    return if seconds.nil? || seconds < MIN_SECONDS

    read = new(key: key.to_s, seconds: [ seconds, MAX_SECONDS ].min)
    read if read.save
  end
end
