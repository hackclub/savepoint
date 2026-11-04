require "test_helper"

class OrderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ADMIN" ]
    @project = projects(:orpheus)
    users(:orpheus).update!(phone_number: HQ_PHONE)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "approved hours are spent like money: one of each prize, as many as they cover" do
    assert_not buy_prize("micro").persisted?, "nothing approved yet"

    micro, u2c = Prize.find("micro"), Prize.find("u2c")
    approve(hours: micro.hours + u2c.hours + 1)
    assert_equal micro.hours + u2c.hours + 1, @project.hours_to_spend

    first = buy_prize("micro")
    assert first.persisted?
    assert first.waiting?
    assert_equal [ "micro", micro.hours.to_d ], [ first.prize_key, first.hours ]
    assert_equal "8BitDo Micro", first.configuration
    assert_equal [ micro.hours, u2c.hours + 1 ], [ @project.reload.hours_spent, @project.hours_to_spend ]

    again = buy_prize("micro")
    assert_not again.persisted?
    assert_equal "8BitDo Micro is one you've bought already", again.problem

    too_much = buy_prize("steam100")
    assert_match(/\AThat's .* hours, and you've .* approved to spend\.\z/, too_much.problem)

    assert buy_prize("u2c").persisted?
    assert_equal 1, @project.reload.hours_to_spend
  end

  test "buying tells the admins what to order" do
    approve(hours: Prize.find("micro").hours)
    buy_prize("micro").then { |order| OrderNotifier.claimed(order) }
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ADMIN" }
    assert_equal "Orpheus the Dino claimed the 8BitDo Micro with #{Prize.find("micro").hours.to_s.delete_suffix(".0")} approved hours. " \
                 "Order it, then mark it ordered.", dm[:args].second
    assert_equal [ "Open the queue", "https://savepoint.hackclub.com/admin/orders" ], dm[:args].third["link"]
  end

  test "a free claim tells the admins without the hours" do
    users(:orpheus).rewards.create!(key: "stickers")
    buy_prize("stickers").then { |order| OrderNotifier.claimed(order) }
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ADMIN" }
    assert_equal "Orpheus the Dino claimed their free Hack Club stickers. Order them, then mark them ordered.",
                 dm[:args].second
  end

  test "the admin DM escapes the name" do
    approve(hours: Prize.find("micro").hours)
    users(:orpheus).update!(name: "<!channel> Orph")
    OrderNotifier.claimed(buy_prize("micro"))
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ADMIN" }
    assert_match(/\A&lt;!channel&gt; Orph claimed/, dm[:args].second)
  end

  test "buying needs an address to post it to, and the order keeps it as it was" do
    approve(hours: Prize.find("micro").hours)
    users(:orpheus).update!(address: nil) # signed in before we asked
    assert_equal "We need an address to post it.", buy_prize("micro").problem

    users(:orpheus).update!(address: HQ_ADDRESS)
    order = buy_prize("micro")
    assert_equal HQ_ADDRESS_WITH_PHONE, order.address
    users(:orpheus).update!(address: HQ_ADDRESS.merge("street_address" => "1 New St"))
    assert_equal "15 Falls Rd", order.reload.address["street_address"]
  end

  test "an admin orders it once, and the bot DMs them" do
    approve(hours: Prize.find("micro").hours)
    order = buy_prize("micro")
    travel_to Time.utc(2026, 11, 6, 12) do
      assert order.ordered!(by: users(:ana))
    end
    assert_equal [ "ordered", users(:ana), Time.utc(2026, 11, 6, 12) ], [ order.status, order.ordered_by, order.ordered_at ]
    assert_not order.ordered!(by: users(:ana))

    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_equal "Your 8BitDo Micro is ordered, yay!! :yayayayayay:", dm[:args].second
  end

  test "a prize in Prize::ALL is spent on by its key: its hours and the address" do
    micro = Prize.find("micro")
    assert_not buy_prize("micro").persisted?, "nothing approved yet"

    approve(hours: micro.hours + 2)
    users(:orpheus).update!(address: HQ_ADDRESS)
    order = buy_prize("micro")
    assert order.persisted?
    assert_equal [ "micro", micro.hours.to_d, HQ_ADDRESS_WITH_PHONE ], [ order.prize_key, order.hours, order.address ]
    assert_equal "8BitDo Micro", order.configuration
    assert_equal 2, @project.reload.hours_to_spend

    assert_equal "That's #{Prize.find("steam100").hours.to_s.delete_suffix(".0")} hours, and you've 2 approved to spend.", buy_prize("steam100").problem
    assert_not buy_prize("not-a-prize").persisted?
    assert_not @project.orders.create.persisted?, "no prize at all"
  end

  test "a banned owner can't claim, and a red Hackatime trust level can't either (D-148)" do
    approve(hours: Prize.find("micro").hours)
    users(:orpheus).update!(banned_at: Time.current, ban_reason: "fraud")
    assert_equal "This account can't claim prizes.", buy_prize("micro").problem

    users(:orpheus).update!(banned_at: nil)
    users(:orpheus).update_columns(hackatime_trust_level: "red")
    assert_equal "This account can't claim prizes.", buy_prize("micro").problem

    users(:orpheus).update_columns(hackatime_trust_level: "blue")
    assert buy_prize("micro").persisted?
  end

  test "a ban cancels the waiting orders, which stop counting as spent, and placing a banned order is refused" do
    approve(hours: Prize.find("micro").hours + 1)
    order = buy_prize("micro")
    users(:orpheus).ban!("fraud", by: users(:ana))
    assert order.reload.cancelled?
    assert_equal 0, @project.reload.hours_spent
    assert_raises(Order::Blocked) { order.update_columns(status: "waiting") && order.place!(by: users(:ana)) }
    assert order.reload.waiting?
  end

  test "placing an order again checks the ban, the stickers, and the hours (D-148)" do
    approve(hours: Prize.find("micro").hours)
    order = buy_prize("micro")
    users(:orpheus).update_columns(banned_at: Time.current)
    error = assert_raises(Order::Blocked) { order.place!(by: users(:ana)) }
    assert_match(/is banned/, error.message)
    assert_raises(Order::Blocked) { order.ordered!(by: users(:ana)) }

    users(:orpheus).update_columns(banned_at: nil)
    @project.ships.update_all(approved_hours: 1, review_hours: 1, claimed_hours: 1)
    assert_equal "Their approved hours no longer cover this prize.", assert_raises(Order::Blocked) { order.place!(by: users(:ana)) }.message
    assert order.reload.waiting?

    users(:orpheus).rewards.create!(key: "stickers")
    sticker = buy_prize("stickers")
    users(:orpheus).rewards.destroy_all
    assert_equal "They haven't earned these stickers.", assert_raises(Order::Blocked) { sticker.place!(by: users(:ana)) }.message
  end

  test "lifting a ban needs a reason, restores the cancelled orders and keeps the ban's reason" do
    approve(hours: Prize.find("micro").hours)
    order = buy_prize("micro")
    user = users(:orpheus)
    user.ban!("copied game", by: users(:ana))
    assert_not user.lift_ban!("  ", by: users(:ana))
    assert user.reload.banned?

    assert user.lift_ban!("wrongly flagged", by: users(:ana))
    assert_not user.reload.banned?
    assert_match(/wrongly flagged.*copied game/, user.ban_reason)
    assert order.reload.waiting?
    assert_not user.lift_ban!("again", by: users(:ana))
  end

  test "a posted prize needs a postal code where the country has one, and a phone (D-148)" do
    approve(hours: Prize.find("micro").hours + Prize.find("u2c").hours + Prize.find("k617").hours)
    no_postal = HQ_ADDRESS_WITH_PHONE.except("postal_code")
    assert_equal "Add the postal code.", @project.reload.orders.create(prize_key: "micro", address: no_postal).problem
    assert_equal "Add a phone number for the carrier.", @project.reload.orders.create(prize_key: "micro", address: HQ_ADDRESS).problem
    assert @project.reload.orders.create(prize_key: "micro", address: no_postal.merge("country" => "HK")).persisted?, "Hong Kong has no postal code"
    assert @project.reload.orders.create(prize_key: "u2c", address: HQ_ADDRESS_WITH_PHONE).persisted?
  end

  test "a prize whose terms say 18 or older needs a birthdate showing it (D-148)" do
    assert Prize.find("ps100").adults_only?
    assert_not Prize.find("xbox100").adults_only?
    approve(hours: Prize.find("ps100").hours)
    user = users(:orpheus)

    assert_equal "We need your birthdate to check you're 18 or older for this prize.", buy_prize("ps100").problem
    user.update!(birthdate: 17.years.ago.to_date.to_s)
    assert_equal "You need to be 18 or older to claim this prize.", buy_prize("ps100").problem
    user.update!(birthdate: 18.years.ago.to_date.to_s)
    assert buy_prize("ps100").persisted?
  end

  test "a code sent by email needs an email (D-148)" do
    approve(hours: Prize.find("aseprite").hours)
    users(:orpheus).update_columns(email: nil)
    assert_equal "We need an email to send it to.", buy_prize("aseprite").problem
    users(:orpheus).update_columns(email: "orpheus@hackclub.com")
    assert buy_prize("aseprite").persisted?
  end

  private
    def buy_prize(key)
      @project.reload.orders.create(prize_key: key)
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

  test "the free stickers can be claimed only by someone who earned them, and cost no hours" do
    users(:orpheus).update!(address: HQ_ADDRESS)
    refused = buy_prize("stickers")
    assert_not refused.persisted?
    assert_equal "Hack Club stickers isn't one you've earned", refused.problem

    users(:orpheus).rewards.create!(key: "stickers")
    order = buy_prize("stickers")
    assert order.persisted?
    assert order.waiting?
    assert_equal [ "stickers", 0 ], [ order.prize_key, order.hours.to_i ]
    assert_equal "Hack Club stickers", order.configuration
    assert_equal 0, @project.reload.hours_spent

    again = buy_prize("stickers")
    assert_not again.persisted?
    assert_equal "Hack Club stickers is one you've bought already", again.problem
  end

  test "a sticker pack can be claimed once for each pack earned, comeback ones included, and never more than 3" do
    users(:orpheus).update!(address: HQ_ADDRESS)
    users(:orpheus).rewards.create!(key: "stickers")
    assert buy_prize("stickers").persisted?
    again = buy_prize("stickers")
    assert_not again.persisted?
    assert_equal "Hack Club stickers is one you've bought already", again.problem

    users(:orpheus).rewards.create!(key: "comeback_stickers_1")
    assert buy_prize("stickers").persisted?
    assert_not buy_prize("stickers").persisted?, "two earned, two claimed"

    users(:orpheus).rewards.create!(key: "comeback_stickers_2")
    assert buy_prize("stickers").persisted?
    assert_equal 3, @project.orders.where(prize_key: "stickers").count

    # A fourth reward is possible by hand (a bug elsewhere), but the order still isn't.
    Reward.insert!({ user_id: users(:orpheus).id, key: "comeback_stickers_3", created_at: Time.current, updated_at: Time.current })
    fourth = buy_prize("stickers")
    assert_not fourth.persisted?
    assert_equal "Hack Club stickers is one you've bought already", fourth.problem
  end

  test "the stickers are not one of the shelf's prizes" do
    assert_nil Prize::ALL.find { |prize| prize.key == "stickers" }
    assert_equal Prize::STICKERS, Prize.find("stickers")
    assert_not_includes Project::PRIZE_KEYS, "stickers"
  end

  test "the free stickers are refused to accounts that are ineligible or Hackatime-banned, and allowed to eligible ones" do
    user = users(:orpheus)
    user.update!(address: HQ_ADDRESS)
    user.rewards.create!(key: "stickers")

    user.update_columns(ysws_eligible: false)
    refused = buy_prize("stickers")
    assert_not refused.persisted?
    assert_equal "Hack Club stickers aren't available on this account", refused.problem

    user.update_columns(ysws_eligible: true, hackatime_trust_level: "red")
    assert_not buy_prize("stickers").persisted?

    user.update_columns(hackatime_trust_level: "blue")
    assert buy_prize("stickers").persisted?
  end
end

# The race: two claims for different prizes, each one that fits alone, but not both. The check and the insert are one step
# under the project's row lock, so only one is saved. Threads each need their own database connection, so nothing here rolls
# back by itself: the test removes what it made.
class OrderConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  # Holds a claim between its check and its insert until the other one has also checked (or a second has passed, which is
  # what happens when the lock keeps the other one out). With no lock, both then insert: the double spend.
  module Rendezvous
    def addressed
      meet = Thread.current[:order_rendezvous]
      if meet
        meet[:mutex].synchronize do
          meet[:arrived] += 1
          meet[:cond].broadcast
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
          while meet[:arrived] < 2 && (left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)) > 0
            meet[:cond].wait(meet[:mutex], left)
          end
        end
      end
      super
    end
  end
  Order.prepend(Rendezvous)

  test "parallel claims of different prizes spend the approved hours once" do
    project = projects(:orpheus)
    micro, aseprite = Prize.find("micro"), Prize.find("aseprite")
    assert_operator micro.hours + aseprite.hours, :>, 7
    assert_operator [ micro.hours, aseprite.hours ].max, :<=, 7

    project.user.update!(phone_number: HQ_PHONE) # not transactional: undone below
    approve(project, hours: 7)
    start = Queue.new
    meet = { mutex: Mutex.new, cond: ConditionVariable.new, arrived: 0 }
    threads = %w[micro aseprite].map do |key|
      Thread.new do
        Thread.current[:order_rendezvous] = meet
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          Project.find(project.id).orders.create(prize_key: key)
        end
      end
    end
    2.times { start << true }
    orders = threads.map(&:value)

    assert_equal 1, orders.count(&:persisted?), "exactly one claim is saved"
    assert_equal 1, Order.where(project_id: project.id).count
    assert_operator Project.find(project.id).hours_spent, :<=, 7
    refused = orders.find { |order| !order.persisted? }
    assert_match(/approved to spend\.\z/, refused.problem)
  ensure
    Order.where(project_id: project.id).delete_all
    project.ships.destroy_all
    project.user.streak_activities.delete_all
    project.user.update!(phone_number: nil)
  end

  test "parallel claims of the stickers take no more packs than were earned" do
    project, user = projects(:orpheus), users(:orpheus)
    address = user.address
    user.update!(address: HQ_ADDRESS)
    Reward.create!(user:, key: "stickers")
    start = Queue.new
    meet = { mutex: Mutex.new, cond: ConditionVariable.new, arrived: 0 }
    threads = 2.times.map do
      Thread.new do
        Thread.current[:order_rendezvous] = meet
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          Project.find(project.id).orders.create(prize_key: "stickers")
        end
      end
    end
    2.times { start << true }
    orders = threads.map(&:value)

    assert_equal 1, orders.count(&:persisted?), "one pack earned, one claim saved"
    assert_equal 1, Order.where(project_id: project.id).count
  ensure
    Order.where(project_id: project.id).delete_all
    Reward.where(user_id: user.id, key: Reward::STICKER_KEYS).delete_all
    user.update!(address:)
  end

  private
    # As OrderTest#approve: the hours Hackatime logged since Save Point began (D-003), approved on a ship.
    def approve(project, hours:)
      travel_to(Program::STARTS_AT + 2.days) do
        project.user.streak_activities.find_or_initialize_by(activity_date: (Program::STARTS_AT + 1.day).to_date).update!(coded_seconds: (hours * 3600).to_i)
        project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, and it is a game.",
                              repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours:,
                              screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
                .tap { approve_through_fraud(it) }
      end
    end
end
