# The shop: every prize in Prize::ALL, fewest hours first, each as a card. Everything is in hours: approved hours are
# spent like money (Project#hours_to_spend), one claim per prize (Order). What the counter says is in the nudges'
# voice (Nudge::Copy): a plain, short, lowercase line.
module ShopHelper
  CLAIMED_TAGS = { "waiting" => "in the queue", "ordered" => "ordered" }.freeze

  # Your order for a prize, if you've claimed it.
  def shop_order_for(project, prize)
    project.orders.find { |order| order.persisted? && order.prize_key == prize.key }
  end

  # Where a card is: claimed (you've an order for it), ready (your approved hours cover it: claim it) or locked (they
  # don't yet). Without a project (the public shop) it's just on show.
  def shop_state(project, prize, order)
    if project.nil? then "public"
    elsif order then "claimed"
    elsif project.hours_to_spend >= prize.hours then "ready"
    else "locked"
    end
  end

  # The shelf as cards: { prize:, goal:, order:, state:, needed: } for each prize in Prize::ALL. `goal` is the prize
  # the project is aiming for, `needed` the approved hours it still lacks.
  def shop_shelf(project)
    Prize::ALL.map do |prize|
      order = project && shop_order_for(project, prize)
      { prize:, goal: project&.chosen_prize == prize, order:, state: shop_state(project, prize, order),
        needed: project ? [ (prize.hours - project.hours_to_spend).round(1), 0 ].max : 0 }
    end
  end

  # Whether to show the free stickers' claim card (D-051): they are earned (the "stickers" Reward) and not yet claimed. They are
  # not one of the shelf's prizes.
  def shop_sticker_claim?(project, user = current_user)
    project.present? && user&.sticker_eligible? && user.earned?("stickers") && shop_order_for(project, Prize::STICKERS).nil?
  end

  # "12 hrs"
  def shop_hours(hours)
    "#{project_hours(hours)} hrs"
  end

  # The line under a card's price: how it stands.
  def shop_card_status(card)
    case card[:state]
    when "claimed" then CLAIMED_TAGS.fetch(card[:order].status)
    when "locked" then "#{project_hours(card[:needed])} more #{card[:needed] == 1 ? "hr" : "hrs"} needed"
    end
  end

  # The ship cell next to your hours: whether you've shipped, and how that went.
  def shop_ship_status(project)
    if project.shipped? then [ "#{project_hours(project.hours_to_spend)} hrs", "done" ]
    elsif project.ship_in_review then [ "in review", "review" ]
    else [ "not yet", "none" ]
    end
  end
end
