# D-066: every tracking project's jame gam submission, every half hour. A new submission is picked up within that.
class JameGamSweepJob < ApplicationJob
  def perform
    if JameGam::Submissions.token.blank?
      Rails.logger.warn("JameGamSweepJob: no jame gam token (JAMEGAM_AIRTABLE_TOKEN), so submissions are not checked.")
      return
    end

    Project.find_each { JameGamRefreshJob.perform_later(it.id) if it.tracking? }
  end
end
