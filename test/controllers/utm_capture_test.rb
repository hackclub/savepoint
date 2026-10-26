require "test_helper"
require_relative "../support/admin_mcp_helpers"

class UtmCaptureTest < ActionDispatch::IntegrationTest
  include AdminMcpHelpers

  test "a tagged visit is recorded, and the first tags are kept in a cookie" do
    assert_difference -> { Visit.count } do
      get root_path, params: { utm_source: " Slack ", utm_medium: "POST", utm_campaign: "launch", utm_content: "", foo: "bar" }
    end

    visit = Visit.last
    assert_equal %w[slack post launch], [ visit.utm_source, visit.utm_medium, visit.utm_campaign ]
    assert_nil visit.utm_content
    assert_equal "/", visit.path
    assert_not_nil cookies[:sp_utm]
    assert_includes response.headers["Set-Cookie"].downcase, "httponly"
  end

  test "the first tags stay, though a later visit is recorded too" do
    get root_path, params: { utm_source: "slack" }
    first = cookies[:sp_utm]
    assert_difference -> { Visit.count } do
      get root_path, params: { utm_source: "twitter" }
    end

    assert_equal first, cookies[:sp_utm]
    assert_equal %w[twitter slack], Visit.order(:id).last(2).reverse.map(&:utm_source)
  end

  test "a visit with no tags is recorded with empty tags, and sets no cookie" do
    assert_difference -> { Visit.count } do
      get root_path, params: { ref: "x", utm_source: "  " }
    end
    assert_equal [ nil, nil, nil, nil, nil ], Visit::TAGS.map { |tag| Visit.last[tag] }
    assert_equal "/", Visit.last.path
    assert_nil cookies[:sp_utm]
  end

  test "only HTML GETs are visits" do
    assert_no_difference -> { Visit.count } do
      get signups_path
      get "/up"
      post "/auth/hackclub"
      get root_path(format: :json)
    end
  end

  test "an admin's page views are not visits, nor are those of an admin viewing as someone" do
    create_insights_views # the admin home reads the funnel from them
    admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ users(:orpheus).slack_id ]
    sign_in_as(users(:orpheus))

    assert_no_difference -> { Visit.count + SiteDay.count } do
      get shop_path
      get admin_root_path
      post admin_user_impersonation_path(users(:ana))
      get shop_path
    end
    assert_nil users(:ana).reload.last_seen_at
    assert_nil users(:orpheus).reload.last_seen_at
  ensure
    Rails.configuration.x.admin_slack_ids = admins
  end

  test "a participant's page view is a visit and marks them as seen, at most once a minute" do
    sign_in_as(users(:ana))
    freeze_time do
      assert_difference -> { Visit.count }, 1 do
        get shop_path
      end
      assert_equal [ [ users(:ana).id, StreakActivity.streak_date_for(Time.current, users(:ana).timezone) ] ], SiteDay.pluck(:user_id, :date)
      assert_equal [ Time.current, "/shop" ], [ users(:ana).reload.last_seen_at, users(:ana).last_seen_path ]
    end

    travel 30.seconds do
      get project_path
      assert_equal "/shop", users(:ana).reload.last_seen_path
    end
    travel 61.seconds do
      get project_path
      assert_equal "/project", users(:ana).reload.last_seen_path
    end
  end

  test "a signed-out visit marks nobody as seen" do
    get root_path
    assert_nil User.where.not(last_seen_at: nil).first
  end

  test "a value is cut to 100 characters, and the path holds no query string" do
    get root_path, params: { utm_source: "a" * 300 }

    assert_equal 100, Visit.last.utm_source.size
    assert_not_includes Visit.last.path, "?"
  end

  test "a failure to record never breaks the page" do
    Visit.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid }
    begin
      get root_path, params: { utm_source: "slack" }
    ensure
      Visit.singleton_class.remove_method(:create!)
    end

    assert_response :success
  end

  test "a visit holds no personal data" do
    assert_empty Visit.column_names & %w[ip ip_address user_agent user_id referrer email]
    assert_equal %w[created_at id path utm_campaign utm_content utm_medium utm_source utm_term], Visit.column_names.sort
  end

  test "a new user gets the tags of their first visit, and an existing user keeps theirs" do
    mock_hack_club_auth
    get root_path, params: { utm_source: "slack", utm_medium: "post", utm_term: "jam" }
    post "/auth/hackclub"
    follow_redirect!

    user = User.find_by!(hca_id: "ident!heidi")
    assert_equal %w[slack post jam], [ user.utm_source, user.utm_medium, user.utm_term ]

    get root_path, params: { utm_source: "twitter" }
    post "/auth/hackclub"
    follow_redirect!
    assert_equal "slack", user.reload.utm_source
  end

  test "an existing user without tags is not given any by signing in" do
    mock_hack_club_auth(uid: "ident!ana")
    users(:ana).update!(hca_id: "ident!ana")
    get root_path, params: { utm_source: "slack" }
    post "/auth/hackclub"
    follow_redirect!

    assert_nil users(:ana).reload.utm_source
  end

  test "a new user with no cookie has no tags" do
    mock_hack_club_auth
    post "/auth/hackclub"
    follow_redirect!

    assert_nil User.find_by!(hca_id: "ident!heidi").utm_source
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
