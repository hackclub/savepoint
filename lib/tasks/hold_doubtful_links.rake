# D-087: a hand-picked Hackatime link that shares nothing with the game's title or repo needs a Yes. The next sync of each
# person holds its time by itself; this does it now, from what's stored, without asking Hackatime. Safe to run again.
namespace :hackatime do
  desc "Hold the time on doubtful hand-picked Hackatime links until the person says yes (D-087); DRY_RUN=1 only lists them"
  task hold_doubtful_links: :environment do
    marked = Project.where(hackatime_auto_linked: false, hackatime_link_confirmed: false).includes(:user).select(&:hackatime_link_doubtful?)
    marked.each do |project|
      puts "project #{project.id} (#{project.title}) -> #{project.hackatime_projects.join(", ")}"
      next if ENV["DRY_RUN"].present?

      CodedBucket.where(user_id: project.user_id).where("seconds > 0").update_all("unconfirmed_seconds = seconds, seconds = 0")
      StreakActivity.where(user_id: project.user_id).where("coded_seconds > 0")
                    .update_all("unconfirmed_seconds = unconfirmed_seconds + coded_seconds, coded_seconds = 0, updated_at = CURRENT_TIMESTAMP")
      project.user.recalculate_streak!
    end
    puts "#{marked.size} doubtful links#{" (dry run)" if ENV["DRY_RUN"].present?}: project ids #{marked.map(&:id).join(", ")}"
  end
end
