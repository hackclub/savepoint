require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see everyone, with a way to view as anyone who isn't an admin" do
    sign_in_as(users(:orpheus))
    get admin_users_path

    assert_response :success
    assert_select "tr##{dom_id(users(:ana))}", text: /Ana Lovelace.*ana@hackclub\.com.*pixelana/m
    assert_select "tr##{dom_id(users(:ana))} form[action=?]", admin_user_impersonation_path(users(:ana))
    assert_select "tr##{dom_id(users(:orpheus))} form", 0
    assert_select "tr##{dom_id(users(:orpheus))}", text: /admin/
  end

  test "shows the prize each person picked, with its image, and none for someone with no pledge" do
    nobody = User.create!(hca_id: "ident!nobody", name: "No Pledge", email: "nopledge@example.com", slack_id: "U0NOPLEDGE", slack_display_name: "nopledge")
    sign_in_as(users(:orpheus))
    get admin_users_path

    assert_response :success
    assert_select "tr##{dom_id(users(:ana))} td[data-label=Goal]", text: /8BitDo Ultimate 2C/
    assert_select "tr##{dom_id(users(:ana))} td[data-label=Goal] img[alt=?][loading=lazy]", "8BitDo Ultimate 2C"
    assert_select "tr##{dom_id(users(:orpheus))} td[data-label=Goal]", text: /8BitDo Micro/
    assert_select "tr##{dom_id(nobody)} td[data-label=Goal]", text: /none/
    assert_select "tr##{dom_id(nobody)} td[data-label=Goal] img", 0
  end

  test "searching narrows it" do
    sign_in_as(users(:orpheus))
    get admin_users_path(q: "pixel")

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "tr##{dom_id(users(:ana))}"
  end

  test "nobody else can see it" do
    get admin_users_path
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_users_path
    assert_response :not_found
  end

  test "the list links each name and picture to the person's page" do
    sign_in_as(users(:orpheus))
    get admin_users_path

    assert_select "tr##{dom_id(users(:ana))} a.admin-person[href=?]", admin_user_path(users(:ana)), text: /Ana Lovelace/
    assert_select "tr##{dom_id(users(:ana))} a.admin-person-avatar[href=?]", admin_user_path(users(:ana))
  end

  test "a person's page shows who they are and their project, with its ships and orders" do
    ana = users(:ana)
    sign_in_as(users(:orpheus))
    get admin_user_path(ana)

    assert_response :success
    assert_select "h1", text: /Ana Lovelace/
    assert_select ".au__details dd", text: "ana@hackclub.com"
    assert_select "form[action=?]", admin_user_impersonation_path(ana)
    assert_select ".au__card", 1
    assert_select ".au__card-title a[href=?]", admin_project_path(ana.project), text: ana.project.title
    assert_select ".au__card .au__chip"
    assert_select ".au__card", text: /8BitDo Ultimate 2C/
    ana.project.ships.each { |ship| assert_select ".au__card a[href=?]", admin_ship_path(ship) } if ana.project.ships.any?
  end

  test "a person with no project gets the empty state, and an admin has no view-as" do
    nobody = User.create!(hca_id: "ident!nobody2", name: "No Pledge", email: "nopledge2@example.com", slack_id: "U0NOPLEDGE2", slack_display_name: "nopledge2")
    sign_in_as(users(:orpheus))

    get admin_user_path(nobody)
    assert_response :success
    assert_select ".au__empty", text: "No pledge yet."
    assert_select ".au__card", 0

    get admin_user_path(users(:orpheus))
    assert_response :success
    assert_select "form[action=?]", admin_user_impersonation_path(users(:orpheus)), 0
    assert_select ".au__admin", text: /admin/
  end

  test "a person's page is a not found for everyone but admins" do
    get admin_user_path(users(:ana))
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_user_path(users(:ana))
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
