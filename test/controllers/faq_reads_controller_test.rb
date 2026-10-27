require "test_helper"

# The beacon the landing FAQ sends as a question closes (D-094).
class FaqReadsControllerTest < ActionDispatch::IntegrationTest
  KEY = "shipping.what-does-my-repository-need".freeze

  setup { @admins = Rails.configuration.x.admin_slack_ids }
  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "a read is stored with the key and seconds only" do
    assert_difference("FaqRead.count", 1) { post faq_reads_path, params: { key: KEY, seconds: 14 } }

    assert_response :no_content
    read = FaqRead.last
    assert_equal [ KEY, 14 ], [ read.key, read.seconds ]
  end

  test "it works without the CSRF token, as sendBeacon sends it" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_difference("FaqRead.count", 1) { post faq_reads_path, params: { key: KEY, seconds: 3 } }
    assert_response :no_content
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "an unknown key or too short a read is refused and stores nothing" do
    assert_no_difference("FaqRead.count") do
      post faq_reads_path, params: { key: "made.up", seconds: 5 }
      assert_response :unprocessable_content
      post faq_reads_path, params: { key: KEY, seconds: 0 }
      assert_response :unprocessable_content
      post faq_reads_path, params: { seconds: 5 }
      assert_response :unprocessable_content
    end
  end

  test "a read over ten minutes is stored as ten minutes" do
    post faq_reads_path, params: { key: KEY, seconds: 99_999 }

    assert_equal 600, FaqRead.last.seconds
  end

  test "an admin leaves no trace" do
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!

    assert_no_difference("FaqRead.count") { post faq_reads_path, params: { key: KEY, seconds: 9 } }
    assert_response :no_content
  end

  test "the landing page gives each group its anchor and each question its key" do
    get root_path

    assert_select "div.faq__group#shipping h3", "What counts as a shipped project?"
    %w[basics hours how-to-ship prizes help].each { |slug| assert_select "div.faq__group##{slug}", 1 }
    assert_select "details[id='#{KEY}'][data-faq-key-value='#{KEY}'][data-faq-url-value='#{faq_reads_path}']", 1
    assert_select "details[data-controller=faq]", Faq.keys.size
  end
end
