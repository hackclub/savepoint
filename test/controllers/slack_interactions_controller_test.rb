require "test_helper"

class SlackInteractionsControllerTest < ActionDispatch::IntegrationTest
  test "Slack's click payload gets a 200 with no sign-in, and nothing is made or set" do
    with_forgery_protection do
      assert_no_difference [ -> { User.count }, -> { Visit.count } ] do
        post slack_interactions_path, params: { payload: { type: "block_actions", user: { id: "U0ANA" } }.to_json }
      end
    end

    assert_response :ok
    assert_empty response.body
    assert_nil response.headers["Set-Cookie"]
  end

  private
    def with_forgery_protection
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      yield
    ensure
      ActionController::Base.allow_forgery_protection = original
    end
end
