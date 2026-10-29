# D-066, D-121: every project's jame gam submissions (tracking or not: fraud review wants them for all), every half hour. A new
# submission is picked up within that. The lookups are spread over SPREAD, not sent in one burst, because Airtable allows about
# 5 requests a second to a base and a refused one (429) leaves that project's columns as they were until the next sweep.
class JameGamSweepJob < ApplicationJob
  SPREAD = 5.minutes

  def perform
    if JameGam::Submissions.token.blank?
      Rails.logger.warn("JameGamSweepJob: no jame gam token (JAMEGAM_AIRTABLE_TOKEN), so submissions are not checked.")
      return
    end

    Project.find_each { JameGamRefreshJob.set(wait: rand(SPREAD.to_i).seconds).perform_later(it.id) }
  end
end
