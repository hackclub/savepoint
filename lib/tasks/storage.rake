namespace :storage do
  # Screenshots uploaded before Cloudflare R2 was set up went to the container's disk, which a deploy wipes, so
  # their blobs are still in the database with nothing behind them: the project page shows a broken image and the
  # ship form thinks there's a screenshot. This drops those blobs (and their attachments), so people are asked
  # for the screenshot again.
  #
  #   bin/rails storage:purge_missing
  desc "Purge Active Storage blobs whose file is no longer in storage"
  task purge_missing: :environment do
    checked = purged = 0
    ActiveStorage::Blob.find_each do |blob|
      checked += 1
      next if blob.service.exist?(blob.key)
      blob.attachments.each(&:purge)
      blob.purge
      purged += 1
    end
    puts "#{checked} blobs checked, #{purged} purged"
  end
end
