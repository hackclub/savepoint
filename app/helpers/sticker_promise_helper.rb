# The free stickers' card on the project page (D-051). One helper decides which of its states someone is in, or that there
# is no card at all: the shop's claim card (ShopHelper#shop_sticker_claim?) is where the claim itself happens.
module StickerPromiseHelper
  STICKER_PROGRESS_CACHE = 2.minutes

  # nil (no card), or { kind:, ... }:
  #   :counting inside the first hour and not earned yet. Has :deadline, :tracking (a Hackatime project is linked to the
  #             game), and :seconds (what counts so far; nil when it isn't tracked or can't be read), :minutes, :percent.
  #   :earned   they have them and haven't claimed: the card sends them to the shop.
  #   :claimed  there's an order for them (it waits for an admin to post it).
  # Accounts from before Reward::STICKERS_SINCE, ones that aren't YSWS-eligible or are banned on Hackatime, and ones whose hour passed without earning them, get nothing.
  def sticker_promise_state(user, now: Time.current)
    project = user&.project
    return unless project && user.created_at && user.created_at >= Reward::STICKERS_SINCE && user.sticker_eligible?

    if project.orders.any? { |order| order.persisted? && order.prize_key == Prize::STICKERS.key }
      { kind: :claimed }
    elsif user.earned?("stickers")
      { kind: :earned }
    elsif now < user.created_at + Reward::STICKERS_WINDOW
      sticker_counting_state(user, project)
    end
  end

  # "2 of 5 minutes"
  def sticker_progress_text(state)
    "#{state[:minutes]} of #{Reward::STICKERS_SECONDS / 60} minutes"
  end

  # What the pomodoro's poll (ProjectsController#hours) tells the overlay's strip: nil when there is no promise, else
  # { kind:, minutes:, percent:, text: }. Minutes, percent and text are nil where the progress can't be read.
  def sticker_promise_json(state)
    return unless state

    { kind: state[:kind], minutes: state[:minutes], percent: state[:percent],
      text: (sticker_progress_text(state) if state[:kind] == :counting && state[:minutes]) }
  end

  private

  def sticker_counting_state(user, project)
    deadline = user.created_at + Reward::STICKERS_WINDOW
    seconds = (sticker_seconds(user, project) if project.tracking?)
    state = { kind: :counting, deadline:, tracking: project.tracking?, seconds: }
    return state unless seconds

    state.merge(minutes: [ seconds / 60, Reward::STICKERS_SECONDS / 60 ].min,
                percent: [ seconds * 100 / Reward::STICKERS_SECONDS, 100 ].min)
  end

  # What counts so far, as Reward.award_stickers! counts it, kept for a couple of minutes so a page load doesn't always
  # ask Hackatime. A failure isn't kept, and just leaves the progress out.
  def sticker_seconds(user, project)
    window = user.created_at..(user.created_at + Reward::STICKERS_WINDOW)
    sticker_progress_cache.fetch([ "sticker-seconds", user.id, user.created_at.to_i, project.hackatime_projects ], expires_in: STICKER_PROGRESS_CACHE) do
      Hackatime.seconds_between(user, project.hackatime_projects, window)
    end
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    nil
  end

  # The test environment's Rails.cache is a null store, so its test gives this a store of its own.
  def sticker_progress_cache = Rails.cache
end
