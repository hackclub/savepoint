# Active Storage draws a direct upload endpoint, POST /rails/active_storage/direct_uploads.
# Nothing in the app uses it. Screenshots are posted as multipart files.
# The endpoint needs no sign-in and skips CSRF. It lets anyone create a blob
# with a content type and size of their own choosing, and returns a presigned PUT URL.
# So it answers 404 here. The blob redirect and representation routes stay,
# because url_for(attachment) needs them.
module DirectUploadsDisabled
  def create
    head :not_found
  end
end

Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.prepend(DirectUploadsDisabled)
end
