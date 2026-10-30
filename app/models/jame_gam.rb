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

  # D-122: the sentence the review page shows for one status.
  def self.status_line(status)
    status.blank? ? "This project hasn't been reviewed in jame gam yet" : "This project was marked as #{status} in jame gam"
  end
end
