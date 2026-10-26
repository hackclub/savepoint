require "application_system_test_case"

class ShopTest < ApplicationSystemTestCase
  setup do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    visit onboarding_path
    execute_script(<<~JS)
      const form = document.createElement("form")
      form.method = "post"
      form.action = "/auth/hackclub"
      document.body.append(form)
      form.submit()
    JS
    assert_current_path onboarding_path
    visit shop_path
  end

  test "the shop lists every prize with the goal marked" do
    assert_selector ".shop-prize", count: Prize::ALL.size
    assert_selector ".shop-prize--goal", count: 1 # Orpheus aims for the 8BitDo Micro
  end

  test "setting a goal from a sheet moves that prize to the top" do
    users(:orpheus).project.update!(prize_key: "u2c")
    visit shop_path
    assert_equal "shop-u2c", first(".shop-prize")[:id]

    find("#shop-aseprite > button.shop-card").click
    wait_for_sheet "#shop-aseprite dialog"
    within("#shop-aseprite dialog") { click_button "Set as my goal" }

    assert_selector ".shop-prize:first-child#shop-aseprite" # the form waits 300 ms for its sound, then reloads
    assert_selector ".shop-prize--goal", count: 1
    assert_selector "#shop-aseprite.shop-prize--goal"
  end

  test "a tag opens its sheet, and claiming asks for the name for the parcel" do
    project = users(:orpheus).project
    link_hackatime(project.user)
    project.update!(hackatime_projects: [ "rhythm-game" ])
    log_hours(project.user, 10)
    project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, and it is a game.",
                          repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours: 10,
                          screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
           .tap { approve_through_fraud(it) }
    visit shop_path
    assert_no_selector ".shop__parcel"

    find("#shop-aseprite > button.shop-card").click
    wait_for_sheet "#shop-aseprite dialog"
    within "#shop-aseprite dialog" do
      assert_text Prize.find("aseprite").facts.first
      assert_text "Set as my goal"
      click_button "Claim it"
      assert_field "Name for the parcel", with: users(:orpheus).reload.name
      assert_text "We only use your name and address to post your prize."
      assert_field "Street address", with: "15 Falls Rd" # from Hack Club, and theirs to change
      assert_field "Country", with: "US"
      assert_text "left after claiming"
      fill_in "Name for the parcel", with: "Orph D"
      click_button "Claim it"
      assert_text "Claimed!"
      assert_text "The #{Prize.find("aseprite").name} is yours"
    end

    assert_selector "#shop-aseprite[data-state=claimed]"
    assert_selector ".shop__notice", text: "You claimed the #{Prize.find("aseprite").name}"
    assert_selector "#shop-aseprite.shop-prize--just-claimed"
    assert_equal "Orph D", users(:orpheus).reload.preferred_name
    assert_equal "Orph D", project.orders.last.recipient_name
  end

  test "someone who earned the free stickers claims them from the card above the grid" do
    users(:orpheus).rewards.create!(key: "stickers")
    visit shop_path
    assert_selector ".shop-prize", count: Prize::ALL.size

    within "#shop-stickers" do
      click_button "Claim your stickers"
      assert_field "Name for the parcel", with: users(:orpheus).reload.name
      assert_field "Street address", with: "15 Falls Rd"
      assert_no_text "hrs left after claiming"
      click_button "Claim it"
      assert_text "Claimed!"
    end

    assert_no_selector "#shop-stickers"
    order = users(:orpheus).project.orders.find_by!(prize_key: "stickers")
    assert order.waiting?
    assert_equal 0, order.hours.to_i
  end

  test "claiming the free stickers from the project page is one click: the sheet opens on the form, and the X closes it" do
    users(:orpheus).update_column(:created_at, Time.utc(2026, 10, 25, 10)) # after STICKERS_SINCE, so the project page has the card
    users(:orpheus).rewards.create!(key: "stickers")
    visit project_path
    click_link "Claim your stickers"

    assert_current_path shop_path # the ?claim=stickers parameter is cleaned out of the address
    assert_selector "#shop-stickers dialog[open]"
    wait_for_sheet "#shop-stickers dialog"
    within "#shop-stickers dialog" do
      assert_selector ".order-sheet__name", text: "Hack Club stickers"
      assert_selector ".order-sheet__kind", text: "Free sticker pack"
      assert_field "Street address", with: "15 Falls Rd"
      assert_no_selector ".order-sheet__facts"
      assert_no_text "If this item is unavailable"
      assert_no_selector "[aria-label=Back]"
      assert_selector "button[aria-label=Close]"
      find("button[aria-label=Close]").click
    end
    assert_no_selector "#shop-stickers dialog[open]"

    # Without the parameter a reload leaves it closed; the card's own button opens it on the form again, and Escape closes it.
    visit shop_path
    assert_no_selector "#shop-stickers dialog[open]"
    click_button "Claim your stickers"
    assert_selector "#shop-stickers dialog[open] [name='address[street_address]']"
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#shop-stickers dialog[open]"

    visit project_path
    click_link "Claim your stickers"
    wait_for_sheet "#shop-stickers dialog"
    within "#shop-stickers dialog" do
      fill_in "Name for the parcel", with: "Orph D"
      click_button "Claim it"
      assert_text "Claimed!"
    end
    order = users(:orpheus).project.orders.find_by!(prize_key: "stickers")
    assert order.waiting?
    assert_equal "Orph D", order.recipient_name
  end

  test "a regular prize's sheet still opens on its preview step, not the form" do
    find("#shop-aseprite > button.shop-card").click
    wait_for_sheet "#shop-aseprite dialog"
    within "#shop-aseprite dialog" do
      assert_selector ".order-sheet__facts"
      assert_no_selector "[name='address[street_address]']"
    end
  end
end
