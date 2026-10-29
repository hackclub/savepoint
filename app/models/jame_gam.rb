# D-066: the jame gam's Airtable base, read-only. A game with a submission there only counts time after it.
module JameGam
  # D-121: does this review_status flag the game? The jame gam team's status values are not known: the base's choices were not read,
  # because the schema call returns sample records with personal data. The tests and D-066 use "Pending" and "Rejected", and a blank
  # status is a submission nobody has reviewed. So a status that contains reject, flag, fraud or ban (any case) counts. Revisit
  # when the real choices are known.
  FLAGGED = /reject|flag|fraud|\bban/i

  def self.flagged?(status) = status.to_s.match?(FLAGGED)
end
