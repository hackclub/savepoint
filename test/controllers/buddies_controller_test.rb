require "test_helper"

class BuddiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    post "/auth/hackclub"
    follow_redirect!
  end

  test "before you're paired: how it works, and your invite link" do
    get buddy_path

    assert_select "h1", "Build with a friend"
    assert_select ".buddy-rules, .buddy-reward, .pg-buddies__way--soon, .pg-buddies__sticky", count: 0
    assert_no_match(/pair weeks|small rewards|Match me with someone|same tool/, response.body)
    assert_select ".buddy-link__input[value=?]", "www.example.com/b/#{projects(:orpheus).reload.buddy_code}"
    assert_select "form[action=?] input[name=?][value=true]", project_path, "project[buddy_invited]"
  end

  test "copying your link from the project page's buddy card counts as sending it" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)
    get project_path
    assert_select ".project__buddy-ask", /Bring a buddy/

    patch project_path, params: { project: { buddy_invited: true } }
    follow_redirect!
    assert_select ".buddy-card__title", "Invite sent"
    assert_select ".project__buddy-ask", count: 0
  end

  test "paired, the sidebar card and the tab show the two of you" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)
    projects(:orpheus).pair_with(projects(:ana))
    get project_path

    assert_select ".buddy-card__title", "You + pixelana"
    assert_select ".buddy-card__note", "pixelana is building pong"
    assert_select ".project__buddy-ask", count: 0

    get buddy_path
    assert_select "h1", "You + pixelana"
    assert_select ".buddy-hours__name", count: 2
    assert_select "#buddies-week-title", /Today/
    assert_select ".buddy-hours__value", /0 of \d+ min/
    assert_select ".buddy-hours__row[data-done]", count: 0, message: "an empty day is not done"
    assert_select ".buddy-reward", count: 0
    assert_select ".pg-buddies__streak-label", /Together/
    assert_select ".pg-buddies__streak-value", /0\.0 hrs/
    assert_select ".pg-buddies__streak-note", "you 0.0 · them 0.0"
    assert_no_match(/pair weeks/i, response.body)
  end

  test "your buddy is their Slack username without a display name, and never their full name" do
    users(:ana).update!(slack_display_name: nil, slack_username: "ana.l")
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)
    projects(:orpheus).pair_with(projects(:ana))

    [ project_path, buddy_path ].each do |path|
      get path
      assert_match(/You \+ (<a [^>]*><span [^>]*>)?ana\.l/, response.body) # their name may be a Slack link
      assert_no_match(/Ana Lovelace|Lovelace/, response.body)
    end
  end
end
