require "test_helper"

class ShopControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ADMIN" ]
    @project = projects(:orpheus)
    @project.update!(prize_key: "u2c")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "without a project it's the public shop: every prize and what it takes, nothing claimable, and a way to start" do
    get shop_path
    assert_response :success
    assert_select ".shop-prize", Prize::ALL.size
    assert_select ".shop-prize[data-state=public]", Prize::ALL.size
    assert_select ".shop-prize--goal", 0
    assert_select ".shop-tag__action", 0
    assert_select "form[action=?]", shop_order_path, 0
    assert_select ".shop-prize dialog.order-sheet a[href=?]", onboarding_path, text: "Start"
    assert_select ".shop__stat", 0
    assert_select ".shop__keeper", 0
    assert_select ".top-bar__nav a[aria-current=page]", /Shop/
    assert_select ".shop__title-text", "Shop"
  end

  test "the shop lists every prize, fewest hours first, with its image, name, kind and hours" do
    sign_in_orpheus
    get shop_path
    assert_response :success

    assert_select ".shop-prize", Prize::ALL.size
    ids = Prize::ALL.map { |prize| "shop-#{prize.key}" }
    assert_equal [ "shop-u2c" ] + (ids - [ "shop-u2c" ]), css_select(".shop-prize").map { |card| card["id"] }, "the goal first, the rest fewest hours first"
    assert_select "#shop-aseprite .shop-card__name", "Aseprite"
    assert_select "#shop-aseprite .shop-card__kind", "Pixel art editor (Steam key)"
    assert_select "#shop-aseprite .shop-card__art img[src*=aseprite]"
    assert_select "#shop-aseprite .shop-card__total", "#{Prize.find("aseprite").hours.to_s.delete_suffix(".0")} hrs total"
    assert_select ".shop__stat--logged .shop__stat-label", "LOGGED"
    assert_select ".shop__stat--ship .shop__stat-label", "TO SPEND"
    page = Nokogiri::HTML5(response.body)
    page.css("script").each(&:remove)
    assert_no_match(/console|handheld/i, page.to_html)
  end

  test "your goal is marked, and a prize you can't pay for says how many more hours it takes" do
    sign_in_orpheus
    get shop_path

    assert_select ".shop-prize--goal", 1
    assert_select "#shop-u2c.shop-prize--goal"
    assert_select ".shop-prize__flag", 0
    assert_select ".shop-prize[data-state=locked]", Prize::ALL.size
    assert_select "#shop-aseprite .shop-prize__status", "#{Prize.find("aseprite").hours.to_s.delete_suffix(".0")} more hrs needed"
    assert_select ".shop-tag__action", 0
    assert_select "form[action=?]", shop_order_path, 0
  end

  test "a prize your approved hours cover has a Claim button, and the ones above it don't" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus
    get shop_path

    assert_select ".shop__stat--ship .shop__stat-value", "#{Prize.find("micro").hours.to_s.delete_suffix(".0")} hrs"
    affordable = Prize::ALL.select { |prize| prize.hours <= Prize.find("micro").hours }
    assert_select ".shop-prize[data-state=ready]", affordable.size
    assert_select "#shop-micro form[action=?] button", shop_order_path, text: /Claim/
    assert_select "#shop-micro input[name='order[prize_key]'][value=micro]"
    assert_select "#shop-steam100 form[action=?]", shop_order_path, 0
    assert_select "#shop-steam100 .shop-prize__status", /more hrs needed/
  end

  test "claiming spends the hours, makes an order for that prize and tells the admins, and it shows as claimed" do
    micro = Prize.find("micro")
    approve(hours: micro.hours + 1)
    sign_in_orpheus

    assert_difference -> { @project.orders.count }, 1 do
      post shop_order_path, params: { order: { prize_key: "micro" } }
    end
    assert_redirected_to shop_path
    order = @project.orders.last
    assert_equal [ "micro", micro.hours.to_d, "waiting" ], [ order.prize_key, order.hours, order.status ]
    assert_equal HQ_ADDRESS.merge("phone_number" => "+18025550123"), order.address, "a claim with no form keeps their Hack Club address and phone"
    assert_equal 1, @project.reload.hours_to_spend
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ADMIN" }
    assert_match(/claimed the 8BitDo Micro with #{micro.hours.to_s.delete_suffix(".0")} approved hours\. Order it, then mark it ordered\./, dm[:args].second)

    follow_redirect!
    assert_select "#shop-micro[data-state=claimed] .shop-prize__status", /in the queue/
    assert_select "#shop-micro form[action=?]", shop_order_path, 0
    assert_select "#shop-micro .order-sheet__status", /In the queue to be ordered/
    assert_select ".shop__keeper", 0
    assert_select ".shop__stat--ship .shop__stat-value", "1 hrs"
  end

  test "the shop page has no parcel name field: it sits in each claimable prize's sheet, prefilled" do
    micro = Prize.find("micro")
    approve(hours: micro.hours + 1)
    sign_in_orpheus

    get shop_path
    assert_select "form[action=?]", "/shop/preferred_name", 0
    assert_select ".shop__parcel", 0
    assert_select "#shop-micro dialog.order-sheet form[action=?]", shop_order_path do
      assert_select "input[name=preferred_name][value=?]", users(:orpheus).reload.name
      assert_select ".sp-label", "Name for the parcel"
      assert_select ".sp-help", /We only use your name and address to post your prize/
      assert_select "input[name='order[prize_key]'][value=micro]"
    end
    assert_select "#shop-aseprite dialog form[action=?]", shop_order_path
    assert_select "#shop-u2 dialog form[action=?]", shop_order_path, 0
    assert_select "#shop-micro dialog .order-sheet__pace", /1 hrs left after claiming/
  end

  test "with no preferred name a claim goes to the Hack Club name" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus
    post shop_order_path, params: { order: { prize_key: "micro" } }
    assert_equal users(:orpheus).reload.name, @project.orders.last.recipient_name
  end

  test "the claim sheet sends the parcel name with the order: saved on the user, kept on the order" do
    approve(hours: Prize.find("micro").hours + Prize.find("aseprite").hours)
    sign_in_orpheus

    post shop_order_path, params: { order: { prize_key: "micro" }, preferred_name: " Orph\nDino " }
    assert_redirected_to shop_path
    assert_equal "Orph Dino", users(:orpheus).reload.preferred_name
    assert_equal "Orph Dino", @project.orders.find_by(prize_key: "micro").recipient_name

    post shop_order_path, params: { order: { prize_key: "aseprite" }, preferred_name: "" }
    assert_nil users(:orpheus).reload.preferred_name
    assert_equal users(:orpheus).name, @project.orders.find_by(prize_key: "aseprite").recipient_name
    assert_equal "Orph Dino", @project.orders.find_by(prize_key: "micro").reload.recipient_name, "an order keeps the name it was claimed with"
  end

  test "a parcel name that is just the Hack Club name is stored as none" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus
    users(:orpheus).reload.update!(preferred_name: "Old Name")

    post shop_order_path, params: { order: { prize_key: "micro" }, preferred_name: users(:orpheus).name }
    assert_nil users(:orpheus).reload.preferred_name
    assert_equal users(:orpheus).name, @project.orders.last.recipient_name
  end

  test "after a claim the shop says so near the top and marks that prize's tag" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus
    post shop_order_path, params: { order: { prize_key: "micro" } }
    follow_redirect!

    assert_select ".shop__notice[role=status]", /You claimed the 8BitDo Micro/
    assert_select ".shop-prize--just-claimed", 1
    assert_select "#shop-micro.shop-prize--just-claimed"
    assert_select ".shop__keeper", 0
    get shop_path
    assert_select ".shop__notice", 0
    assert_select ".shop-prize--just-claimed", 0
  end

  test "a claim that fails without JavaScript shows its error near the top of the shop" do
    sign_in_orpheus
    post shop_order_path, params: { order: { prize_key: "micro" } }
    follow_redirect!

    assert_select ".shop__notice[role=alert]", /hours, and you've 0 approved to spend/
    assert_select ".shop-prize--just-claimed", 0
  end

  test "a claim by fetch answers with where to go, and the sheet has its claimed state ready" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus
    get shop_path
    assert_select "#shop-micro dialog .order-sheet__done[hidden][role=status]" do
      assert_select ".order-sheet__done-title", "Claimed!"
      assert_select ".order-sheet__done-text", /8BitDo Micro is yours/
      assert_select "a[href=?]", shop_path
    end
    post shop_order_path, params: { order: { prize_key: "micro" } }, as: :json
    assert_response :success
    assert_equal({ "redirect" => shop_path }, response.parsed_body)
  end

  test "a parcel name that is too long claims nothing and says why" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus

    assert_no_difference -> { Order.count } do
      post shop_order_path, params: { order: { prize_key: "micro" }, preferred_name: "x" * 121 }
    end
    assert_redirected_to shop_path
    assert_match(/too long/, flash[:shop_error])
    assert_nil users(:orpheus).reload.preferred_name
  end

  test "the sheet keeps a prize's terms inside a closed details, and a prize without terms has none" do
    sign_in_orpheus
    get shop_path

    prize = Prize.find("ps100")
    assert_select "#shop-ps100 dialog details.order-sheet__terms:not([open])", 1 do
      assert_select "summary", /Terms/
      assert_select "li", prize.terms.size
      assert_select "li", /parent or guardian/
    end
    assert_select "#shop-xbox100 dialog details.order-sheet__terms li", Prize.find("xbox100").terms.size
    assert_select "#shop-micro dialog details", 0
  end

  test "each tag opens a sheet: what it is, what it takes, and what you can do with it" do
    micro = Prize.find("micro")
    approve(hours: micro.hours - 1)
    sign_in_orpheus
    get shop_path

    assert_select ".shop-prize", Prize::ALL.size
    assert_select ".shop-prize > button.shop-card[aria-haspopup=dialog]", Prize::ALL.size
    assert_select ".shop-prize dialog.order-sheet", Prize::ALL.size
    assert_select "#shop-micro dialog .order-sheet__facts li", micro.facts.size
    assert_select "#shop-micro dialog .order-sheet__meter-row", /#{micro.hours - 1} of #{micro.hours} hrs.*1 more hr/m
    assert_select "#shop-micro dialog .order-sheet__pace", /a day/
    assert_select "#shop-micro dialog form[action=?]", shop_order_path, 0
    assert_select "#shop-micro dialog form[action=?]", project_path do
      assert_select "input[name=return_to][value=shop]"
      assert_select "input[name='project[prize_key]'][value=micro]"
    end
    assert_select "#shop-u2c dialog .order-sheet__status--goal", /Your goal/
    assert_select "#shop-u2c dialog form[action=?]:not([hidden])", project_path, 0 # both are drawn, so the sheet can swap them at once
    assert_select "#shop-u2c dialog form[action=?][hidden]", project_path
    assert_select "#shop-micro dialog .order-sheet__status--goal[hidden]"
  end

  test "setting a goal from a sheet comes back to the shop" do
    sign_in_orpheus
    patch project_path, params: { return_to: "shop", project: { prize_key: "micro" } }
    assert_redirected_to shop_path
    assert_equal "micro", @project.reload.prize_key
  end

  test "a prize can be claimed once, and not without the hours" do
    micro = Prize.find("micro")
    approve(hours: micro.hours)
    sign_in_orpheus

    post shop_order_path, params: { order: { prize_key: "micro" } }
    assert_equal 1, @project.orders.count
    post shop_order_path, params: { order: { prize_key: "micro" } }
    assert_redirected_to shop_path
    assert_equal 1, @project.orders.count
    assert_match(/8BitDo Micro is one you've bought already/, flash[:shop_error])

    post shop_order_path, params: { order: { prize_key: "steam100" } }
    assert_equal 1, @project.orders.count
    assert_match(/hours, and you've 0 approved to spend/, flash[:shop_error])
  end

  test "an unknown prize can't be claimed" do
    approve(hours: 30)
    sign_in_orpheus
    post shop_order_path, params: { order: { prize_key: "not-a-prize" } }
    assert_equal 0, @project.orders.count
  end

  test "claiming needs a project, and without a Hack Club address the claim step asks for one, empty" do
    post shop_order_path, params: { order: { prize_key: "micro" } }
    assert_redirected_to onboarding_path

    approve(hours: Prize.find("micro").hours)
    users(:orpheus).update!(address: nil, phone_number: nil)
    sign_in_orpheus(address: nil, phone_number: nil)
    get shop_path
    assert_select "form[action^='/auth/hackclub']", 0
    assert_select "#shop-micro form[action=?]", shop_order_path do
      %w[street_address street_address_2 locality region postal_code country phone_number].each do |field|
        assert_select "input[name=?]", "address[#{field}]" do |inputs|
          assert_nil inputs.first["value"], "#{field} starts empty"
        end
      end
    end
  end

  test "the claim step starts from the Hack Club address, every field editable" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus(address: HQ_ADDRESS.merge("street_address" => "15 Falls Rd\nUnit 2"))
    get shop_path
    assert_select "#shop-micro form[action=?]", shop_order_path do
      assert_select "input[name='address[street_address]'][value=?]", "15 Falls Rd"
      assert_select "input[name='address[street_address_2]'][value=?]", "Unit 2"
      assert_select "input[name='address[locality]'][value=?]", "Shelburne"
      assert_select "input[name='address[region]'][value=?]", "VT"
      assert_select "input[name='address[postal_code]'][value=?]", "05482"
      assert_select "input[name='address[country]'][value=?]", "US"
      assert_select "input[name='address[phone_number]'][value=?]", "+18025550123"
      assert_select "input[disabled], input[readonly]", 0
    end
  end

  test "a claim keeps the address they confirmed, not the one from Hack Club, and later changes don't move it" do
    micro = Prize.find("micro")
    approve(hours: micro.hours)
    sign_in_orpheus
    typed = { street_address: " 1 Elm  St\n", street_address_2: "Flat 4", locality: "Leeds", region: "", postal_code: "LS1 1AA", country: "GB", phone_number: "+44 113 496 0000" }

    post shop_order_path, params: { order: { prize_key: "micro" }, address: typed }
    assert_redirected_to shop_path
    order = @project.orders.last
    assert_equal({ "street_address" => "1 Elm St", "street_address_2" => "Flat 4", "locality" => "Leeds", "postal_code" => "LS1 1AA", "country" => "GB",
                   "phone_number" => "+44 113 496 0000" }, order.address)
    assert_equal HQ_ADDRESS, users(:orpheus).reload.address, "their Hack Club address is untouched"
    assert_no_match(/Elm/, Order.connection.select_value("SELECT address FROM orders WHERE id = #{order.id}"), "encrypted at rest")
  end

  test "a claim with a missing field says which, and spends nothing" do
    micro = Prize.find("micro")
    approve(hours: micro.hours)
    sign_in_orpheus
    bad = { street_address: "", locality: " ", country: "", phone_number: "call me" }

    assert_no_difference -> { @project.orders.count } do
      post shop_order_path, params: { order: { prize_key: "micro" }, address: bad }, as: :json
    end
    assert_response :unprocessable_content
    body = response.parsed_body
    assert_equal({ "street_address" => "Add the street address.", "locality" => "Add the city or town.", "country" => "Add the country.",
                   "phone_number" => "Use digits, spaces and + ( ) - only." }, body["fields"])
    assert_equal "Add the street address.", body["message"]
    assert_not_includes response.body, "call me"

    post shop_order_path, params: { order: { prize_key: "micro" }, address: bad.merge(street_address: "x" * 121, locality: "Leeds", country: "GB", phone_number: "") }
    assert_redirected_to shop_path
    assert_equal "Keep it under 120 characters.", flash[:shop_error]
    assert_equal 0, @project.orders.count
  end

  test "a good claim by fetch answers with where to go" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus
    post shop_order_path, params: { order: { prize_key: "micro" }, address: HQ_ADDRESS }, as: :json
    assert_response :success
    assert_equal({ "redirect" => shop_path }, response.parsed_body)
  end

  test "a malformed address parameter is just a missing address" do
    approve(hours: Prize.find("micro").hours)
    sign_in_orpheus
    post shop_order_path, params: { order: { prize_key: "micro" }, address: "nope" }, as: :json
    assert_response :unprocessable_content
    assert_equal %w[country locality street_address], response.parsed_body["fields"].keys.sort
  end

  test "addresses never reach the log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(address: { street_address: "1 Elm St", locality: "Leeds", postal_code: "LS1" }, preferred_name: "Orph", phone_number: "123")
    assert_equal({ address: "[FILTERED]", preferred_name: "[FILTERED]", phone_number: "[FILTERED]" }, filtered)
  end

  test "no Hack Club round trip is offered in the shop, even viewing as someone" do
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    approve(hours: Prize.find("micro").hours)
    users(:ana).update!(address: nil)
    sign_in_orpheus
    post admin_user_impersonation_path(users(:ana))
    get shop_path
    assert_select "form[action^='/auth/hackclub']", 0
  end

  private
    def sign_in_as(_auth)
      post "/auth/hackclub"
      follow_redirect!
    end

    def sign_in_orpheus(**options)
      sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", **options))
    end

    # Approved hours are the ones Hackatime logged since Save Point began (D-003), so log them after the start first.
    def approve(hours:)
      travel_to(Program::STARTS_AT + 2.days) { approve_at_start(hours:) }
    end

    def approve_at_start(hours:)
      @project.user.streak_activities.find_or_initialize_by(activity_date: (Program::STARTS_AT + 1.day).to_date).update!(coded_seconds: (hours * 3600).to_i)
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, and it is a game.",
                             repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours:,
                             screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
              .tap { approve_through_fraud(it) }
    end

  test "the free stickers' claim card shows only when earned and not yet claimed, and is not in the grid" do
    sign_in_orpheus
    get shop_path
    assert_select "#shop-stickers", 0

    users(:orpheus).rewards.create!(key: "stickers")
    get shop_path
    assert_select "#shop-stickers", 1
    assert_select "#shop-stickers button", text: /Claim your stickers/
    assert_select "#shop-stickers form[action=?]", shop_order_path
    assert_select ".shop-prize", Prize::ALL.size
    assert_select "#shop-stickers.shop-prize", 0
    assert_select "#shop-stickers .order-sheet__field", minimum: 1
    assert_select "#shop-stickers .order-sheet__hours", 0

    users(:orpheus).update!(address: HQ_ADDRESS)
    post shop_order_path, params: { order: { prize_key: "stickers" } }
    assert_redirected_to shop_path
    order = @project.orders.find_by!(prize_key: "stickers")
    assert order.waiting?
    assert_equal 0, order.hours.to_i

    get shop_path
    assert_select "#shop-stickers", 0
  end

  test "comeback packs are claimed one at a time, with their own words on the card, up to the 3 earned" do
    sign_in_orpheus
    users(:orpheus).update!(address: HQ_ADDRESS)
    users(:orpheus).rewards.create!(key: "comeback_stickers_1")
    users(:orpheus).rewards.create!(key: "comeback_stickers_2")
    get shop_path
    assert_select "#shop-stickers .sticker-claim__about", text: "You came back and worked on your game. Tell us where to send them."

    2.times do
      post shop_order_path, params: { order: { prize_key: "stickers" } }
      assert_nil flash[:shop_error]
    end
    assert_equal 2, @project.orders.where(prize_key: "stickers").count
    get shop_path
    assert_select "#shop-stickers", 0

    post shop_order_path, params: { order: { prize_key: "stickers" } }
    assert_match(/bought already/, flash[:shop_error])
    assert_equal 2, @project.orders.where(prize_key: "stickers").count
  end

  test "the sticker sheet opens on its form, with no preview step, and says nothing about unavailable items" do
    sign_in_orpheus
    users(:orpheus).rewards.create!(key: "stickers")
    get shop_path
    assert_select "#shop-stickers[data-prize-sheet-start-value=claim][data-prize-sheet-auto-open-value=false]", 1
    assert_select "#shop-stickers .order-sheet__facts", 0
    assert_select "#shop-stickers .prize-note", 0
    assert_select "#shop-stickers button[aria-label=Close][data-action='prize-sheet#back']", 1
    assert_select "#shop-stickers button[aria-label=Back]", 0
    # A regular prize's sheet keeps its details step.
    assert_select "#shop-aseprite[data-prize-sheet-start-value]", 0
    assert_select "#shop-aseprite .order-sheet__facts", 1
  end

  test "?claim=stickers marks the sticker sheet to open for someone who can claim them, and does nothing otherwise" do
    sign_in_orpheus
    get shop_path(claim: "stickers")
    assert_select "#shop-stickers", 0 # not earned yet

    users(:orpheus).rewards.create!(key: "stickers")
    get shop_path(claim: "stickers")
    assert_select "#shop-stickers[data-prize-sheet-auto-open-value=true]", 1
    get shop_path(claim: "something-else")
    assert_select "#shop-stickers[data-prize-sheet-auto-open-value=false]", 1
    get shop_path
    assert_select "#shop-stickers[data-prize-sheet-auto-open-value=false]", 1

    users(:orpheus).update!(address: HQ_ADDRESS)
    post shop_order_path, params: { order: { prize_key: "stickers" } }
    get shop_path(claim: "stickers") # already claimed
    assert_select "#shop-stickers", 0
    assert_select "[data-prize-sheet-auto-open-value=true]", 0
  end

  test "claiming the stickers without having earned them is refused" do
    sign_in_orpheus
    users(:orpheus).update!(address: HQ_ADDRESS)
    post shop_order_path, params: { order: { prize_key: "stickers" } }

    assert_redirected_to shop_path
    assert_match(/isn't one you've earned/, flash[:shop_error])
    assert_empty @project.orders.where(prize_key: "stickers")
  end

  test "the sticker claim card is gone for an ineligible or Hackatime-banned account that holds the reward" do
    sign_in_orpheus
    users(:orpheus).rewards.create!(key: "stickers")
    get shop_path(claim: "stickers")
    assert_select "#shop-stickers", 1

    users(:orpheus).update_column(:hackatime_trust_level, "red")
    get shop_path(claim: "stickers")
    assert_select "#shop-stickers", 0

    users(:orpheus).update_columns(hackatime_trust_level: "blue", ysws_eligible: false)
    get shop_path(claim: "stickers")
    assert_select "#shop-stickers", 0
  end
end
