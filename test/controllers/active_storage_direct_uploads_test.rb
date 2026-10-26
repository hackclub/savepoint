require "test_helper"

class ActiveStorageDirectUploadsTest < ActionDispatch::IntegrationTest
  test "the direct upload endpoint answers 404 when signed out" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post_direct_upload
    end
    assert_response :not_found
  end

  test "the direct upload endpoint answers 404 when signed in" do
    sign_in_as_orpheus

    assert_no_difference -> { ActiveStorage::Blob.count } do
      post_direct_upload
    end
    assert_response :not_found
  end

  test "a blob redirect URL still works" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x"), filename: "x.png", content_type: "image/png")

    get rails_blob_path(blob)
    assert_response :redirect
    assert_equal 302, response.status
  end

  private
    def post_direct_upload
      post "/rails/active_storage/direct_uploads",
        params: { blob: { filename: "x.png", byte_size: 10, checksum: "abc", content_type: "image/png" } },
        as: :json
    end

    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end
end
