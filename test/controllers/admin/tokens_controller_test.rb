require "test_helper"

class Admin::TokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0ANA" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "an admin makes a token, sees it once with the command, and revokes it" do
    sign_in_as(users(:orpheus))
    get admin_tokens_path
    assert_response :success
    assert_select ".admin__nav a[aria-current=page]", "Tokens"
    assert_select "[data-new-token]", 0

    assert_difference -> { users(:orpheus).admin_tokens.count }, 1 do
      post admin_tokens_path, params: { name: "Claude Code on my laptop" }
    end
    assert_response :success
    token = AdminToken.last
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "[data-new-token] code", /\Aclaude mcp add --transport http savepoint http:\/\/www\.example\.com\/admin\/mcp --header "Authorization: Bearer spat_[\w-]{43}"\z/
    shown = css_select("[data-new-token] code").first.text[/spat_[\w-]{43}/]
    assert_equal AdminToken.digest(shown), token.token_digest
    assert_not_equal shown, token.token_digest
    assert_equal "Claude Code on my laptop", token.name

    get admin_tokens_path
    assert_select "[data-new-token]", 0, "shown once"
    assert_not_includes response.body, shown
    assert_select "tr##{dom_id(token)}", /Claude Code on my laptop.*never/m

    delete admin_token_path(token)
    assert_redirected_to admin_tokens_path
    assert token.reload.revoked?
    follow_redirect!
    assert_select "tr##{dom_id(token)} .sp-badge", /Revoked/
    assert_nil AdminToken.authenticate(shown)
  end

  test "a token needs a name" do
    sign_in_as(users(:orpheus))
    assert_no_difference "AdminToken.count" do
      post admin_tokens_path, params: { name: "  " }
    end
    assert_response :unprocessable_entity
    assert_select ".pg-admin-tokens__error", /needed/
  end

  test "tokens are your own" do
    _, theirs = AdminToken.generate!(user: users(:ana), name: "Ana's")
    sign_in_as(users(:orpheus))
    get admin_tokens_path
    assert_select "tr##{dom_id(theirs)}", 0
    delete admin_token_path(theirs)
    assert_response :not_found
    assert_not theirs.reload.revoked?
  end

  test "nobody else can see the page" do
    get admin_tokens_path
    assert_response :not_found
    post admin_tokens_path, params: { name: "x" }
    assert_response :not_found
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    sign_in_as(users(:ana))
    get admin_tokens_path
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
