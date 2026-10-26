namespace :screenshots do
  # Screenshots saved on the container disk before R2 are gone after a deploy, but their attachments and blobs
  # remain. storage:purge_missing sweeps every blob; this one touches only Project screenshots, and shows what it
  # would drop first. It deletes the rows directly: there is no file left for Active Storage to remove.
  #
  #   bin/rails screenshots:drop_lost             # dry run
  #   CONFIRM=1 bin/rails screenshots:drop_lost
  desc "Drop Project screenshot attachments whose file is missing from storage (CONFIRM=1 to do it)"
  task drop_lost: :environment do
    confirmed = ENV["CONFIRM"] == "1"
    count = 0
    ActiveStorage::Attachment.where(record_type: "Project", name: "screenshot").includes(:blob).find_each do |attachment|
      blob = attachment.blob
      next if blob.service.exist?(blob.key)
      count += 1
      puts "project #{attachment.record_id}: #{blob.filename}"
      next unless confirmed
      attachment.delete
      ActiveStorage::Blob.where(id: blob.id).delete_all unless ActiveStorage::Attachment.exists?(blob_id: blob.id)
    end
    puts "#{count} lost screenshot#{"s" unless count == 1} #{confirmed ? "dropped" : "found (dry run, CONFIRM=1 to drop)"}"
  end
end
