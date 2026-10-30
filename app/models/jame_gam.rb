# D-066: the jame gam's Airtable base, read-only. A game with a submission there only counts time after it.
module JameGam
  # D-122: a review_status other than exactly "Approved" (any case, stripped) is shown to the reviewer. A blank status counts: nobody
  # has reviewed it yet. The base's values (read 2026-10-30): Approved, Rejected, Pending, Prize Only, No Prize, Needs Augie,
  # Stickers Only, and blank.
  def self.flagged?(status) = !status.to_s.strip.casecmp?("Approved")

  # D-122: the distinct statuses, in the base's own words, of the stored submissions of THIS game that are not Approved. A blank
  # status is "" (so it reads as not reviewed). Two statuses that differ only in case or spacing count once.
  def self.unapproved_statuses(submissions)
    submissions.select { it["matches"] && flagged?(it["review_status"]) }.map { it["review_status"].to_s.strip }.uniq(&:downcase)
  end

  # D-122 (2026-10-30 amendment): [status, reason] pairs for the lines, one per distinct status and reason. The reason is the jame gam
  # reviewer's text (Submission#reason), or nil.
  def self.unapproved(submissions)
    submissions.select { it["matches"] && flagged?(it["review_status"]) }
               .map { [ it["review_status"].to_s.strip, it["reason"].to_s.strip.presence ] }
               .uniq { |status, reason| [ status.downcase, reason ] }
  end

  # D-122: the sentence the review page shows for one status, with the reviewer's reason after a colon when there is one.
  def self.status_line(status, reason = nil)
    line = status.blank? ? "This project hasn't been reviewed in jame gam yet" : "This project was marked as #{status} in jame gam"
    reason.present? ? "#{line}: #{reason}" : line
  end
end
