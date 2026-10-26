# Save Point's prizes, each priced in hours from its `cost` in US dollars (wiki/decisions/D-011-sliding-prize-rate.md).
# The rate rises from $4 an hour for the cheapest prize to $6 an hour at $100: rate = 4 + 2 * (cost - cheapest) / (100 - cheapest).
# Hours are cost / rate, rounded up to the half hour. Where the shortlist gives a range, `cost` is the top of it.
# Costs other than 8BitDo's are from search results on 2026-10-22, not live store pages (wiki/reports/report-2026-10-22-prize-shortlist.md).
# `article` is "a" or "an" as the name is said aloud ("an 8BitDo", "a $25 Steam gift card"), for copy like "a prize".
# `image` is a file in app/assets/images/save_point/prizes; `icon` stands in while there's none.
# `facts` are what the shop's detail sheet says about it. Each is from the maker's own product page (checked
# 2026-10-22) and a prize without a confirmed fact has none.
# `terms` (optional) are the small print the sheet shows behind a "Terms" disclosure (D-061).
# The Roblox cards' images and Robux counts are each edition's own card art on the Amazon listing (checked 2026-10-24), not Roblox's own page.
class Prize < Data.define(:key, :name, :article, :kind, :cost, :hours, :image, :icon, :facts, :terms, :url)
  def initialize(facts: [], terms: [], **rest) = super(facts: facts.freeze, terms: terms.freeze, **rest)

  # How many minutes a day `hours` takes from `from` to the end, rounded up to 5 minutes.
  def self.pace_minutes(hours, from: Time.current)
    days = [ (Program::ENDS_AT - [ from, Program::STARTS_AT ].max) / 1.day, 1 ].max
    (hours * 60 / days / 5).ceil * 5
  end

  LOW_RATE = 4
  HIGH_RATE = 6
  HIGH_RATE_COST = 100

  # Dollars an hour for a prize costing `cost`, when the cheapest prize costs `cheapest`.
  def self.rate(cost, cheapest:)
    cost, cheapest = cost.to_s.to_r, cheapest.to_s.to_r
    LOW_RATE + (HIGH_RATE - LOW_RATE) * (cost - cheapest) / (HIGH_RATE_COST - cheapest)
  end

  # Hours for a prize costing `cost`: cost over rate, rounded up to the half hour. Whole hours come back as integers.
  def self.hours_for(cost, cheapest:)
    halves = (cost.to_s.to_r / rate(cost, cheapest:) * 2).ceil
    halves.even? ? halves / 2 : halves / 2.0
  end

  def self.find(key) = CLAIMABLE.find { |prize| prize.key == key }

  # "an 8BitDo Micro": the name with its article, for a sentence.
  def with_article = "#{article} #{name}"

  # "8bitdo.com": where `url` is, for the sheet's link.
  def url_host = URI(url).host.delete_prefix("www.").delete_prefix("shop.")

  def pace_minutes(from: Time.current) = self.class.pace_minutes(hours, from:)

  PRICED = [
    { key: "aseprite", name: "Aseprite", article: "an", kind: "Pixel art editor (Steam key)", cost: 19.99, image: "aseprite.png", icon: "palette-fill", url: "https://www.aseprite.org/",
      facts: [ "Layers, frames and animation tags", "Onion skin to see the frames around the one you draw", "Tiled mode for repeating patterns", "Comes as a Steam key" ] },
    { key: "steam25", name: "$25 Steam gift card", article: "a", kind: "Steam credit", cost: 25, image: "steam-card.png", icon: "steam-fill", url: "https://store.steampowered.com/digitalgiftcards",
      facts: [ "Sent as a digital Steam gift card", "Goes to your Steam account" ] },
    { key: "roblox25", name: "$25 Roblox gift card", article: "a", kind: "Robux credit", cost: 25, image: "roblox25.png", icon: "game-2-fill", url: "https://www.roblox.com/giftcards",
      facts: [ "Sent as a digital code to your email", "2,500 Robux: 2,200 plus a 300 bonus", "Comes with an exclusive virtual item" ] },
    { key: "micro", name: "8BitDo Micro", article: "an", kind: "Pocket controller", cost: 24.99, image: "8bitdo-micro.png", icon: "game-2-fill", url: "https://shop.8bitdo.com/products/8bitdo-micro-bluetooth-gamepad",
      facts: [ "Weighs 24.8 grams", "16 buttons", "Works with Switch and Android", "Firmware can be updated" ] },
    { key: "k617", name: "Redragon K617", article: "a", kind: "60% keyboard", cost: 26, image: "redragon-k617.png", icon: "keyboard-fill", url: "https://redragonshop.com/products/small-mechanical-keyboard",
      facts: [ "60% layout with 61 keys", "Wired", "Hot-swappable switches, red switches fitted", "RGB backlight" ] },
    { key: "u2c", name: "8BitDo Ultimate 2C", article: "an", kind: "Hall effect controller", cost: 29.99, image: "8bitdo-ultimate-2c.png", icon: "game-2-fill", url: "https://shop.8bitdo.com/products/8bitdo-ultimate-2c-wireless-controller",
      facts: [ "Hall effect joysticks" ] },
    { key: "g203", name: "Logitech G203", article: "a", kind: "Gaming mouse", cost: 40, image: "logitech-g203.png", icon: "mouse-fill", url: "https://www.logitechg.com/en-us/shop/p/g203-lightsync-rgb-gaming-mouse",
      facts: [ "Sensitivity from 200 to 8,000 DPI", "Up to 5 DPI presets through Logitech G HUB", "LIGHTSYNC RGB lighting" ] },
    { key: "x3", name: "Attack Shark X3", article: "an", kind: "Wireless mouse", cost: 38, image: "attack-shark-x3.png", icon: "mouse-fill", url: "https://attackshark.com/products/attack-shark-x3-wireless-gaming-mouse-paw3395",
      facts: [ "Weighs 49 grams", "PixArt PAW3395 sensor, up to 26,000 DPI", "Wired USB-C, 2.4GHz and Bluetooth" ] },
    { key: "pro2", name: "8BitDo Pro 2", article: "an", kind: "Hall effect controller", cost: 49.99, image: "8bitdo-pro-2.png", icon: "game-2-fill", url: "https://shop.8bitdo.com/products/8bitdo-pro-2-bluetooth-controller",
      facts: [ "Hall effect joysticks", "Bluetooth, for Switch and Windows" ] },
    { key: "roblox50", name: "$50 Roblox gift card", article: "a", kind: "Robux credit", cost: 50, image: "roblox50.png", icon: "game-2-fill", url: "https://www.roblox.com/giftcards",
      facts: [ "Sent as a digital code to your email", "5,250 Robux: 4,500 plus a 750 bonus", "Comes with an exclusive virtual item" ] },
    { key: "u2", name: "8BitDo Ultimate 2", article: "an", kind: "Wireless controller", cost: 59.99, image: "8bitdo-ultimate-2.png", icon: "game-2-fill", url: "https://shop.8bitdo.com/products/8bitdo-ultimate-2" },
    { key: "k2", name: "Keychron K2", article: "a", kind: "Wireless mechanical keyboard", cost: 60, image: "keychron-k2.png", icon: "keyboard-fill", url: "https://www.keychron.com/products/keychron-k2-wireless-mechanical-keyboard",
      facts: [ "75% layout", "Bluetooth for up to 3 devices, or wired", "Hot-swappable switches", "Backlight with 4 brightness levels" ] },
    { key: "f75", name: "Aula F75", article: "an", kind: "Gasket-mount keyboard", cost: 73, image: "aula-f75.png", icon: "keyboard-fill", url: "https://epomaker.com/products/aula-f75-wired",
      facts: [ "75% layout", "Gasket-mounted for softer typing", "Hot-swappable switches", "Wired over USB-C, with a multi-function knob" ] },
    { key: "roblox75", name: "$75 Roblox gift card", article: "a", kind: "Robux credit", cost: 75, image: "roblox75.png", icon: "game-2-fill", url: "https://www.roblox.com/giftcards",
      facts: [ "Sent as a digital code to your email", "8,000 Robux: 7,000 plus a 1,000 bonus", "Comes with an exclusive virtual item" ] },
    { key: "steam100", name: "$100 Steam gift card", article: "a", kind: "Steam credit", cost: 100, image: "steam-card.png", icon: "steam-fill", url: "https://store.steampowered.com/digitalgiftcards",
      facts: [ "Sent as a digital Steam gift card", "Goes to your Steam account" ] },
    { key: "roblox100", name: "$100 Roblox gift card", article: "a", kind: "Robux credit", cost: 100, image: "roblox100.png", icon: "game-2-fill", url: "https://www.roblox.com/giftcards",
      facts: [ "Sent as a digital code to your email", "11,000 Robux: 10,000 plus a 1,000 bonus", "Comes with an exclusive virtual item" ] },
    { key: "ps100", name: "$100 PlayStation Store gift card", article: "a", kind: "PlayStation Store credit", cost: 100, image: "playstation-card.png", icon: "game-2-fill", url: "https://store.playstation.com/",
      facts: [ "Sent as a digital code to your email", "For the PlayStation Store in your country" ],
      terms: [ "Bought for the PlayStation Store in the country of your address. Codes from one country don't work in another.",
               "Sony only lets account holders aged 18+ redeem wallet codes. A parent or guardian redeems it, then shares their wallet with your account.",
               "Your family's PlayStation settings decide what it can buy.",
               "If we can't buy a card for your country, we'll offer you another prize instead.",
               "It has no cash value, and it can't be swapped once it's sent." ] },
    { key: "xbox100", name: "$100 Xbox gift card", article: "a", kind: "Xbox credit", cost: 100, image: "xbox-card.png", icon: "game-2-fill", url: "https://www.microsoft.com/en-us/store/b/gift-cards",
      facts: [ "Sent as a digital code to your email", "For the Microsoft Store in your country" ],
      terms: [ "Bought for the Microsoft Store in the country of your address. Codes from one country don't work in another.",
               "It goes on your Microsoft account. If you're on a family account, a parent approves purchases above your age limit.",
               "If we can't buy a card for your country, we'll offer you another prize instead.",
               "It has no cash value, and it can't be swapped once it's sent." ] }
  ].freeze

  CHEAPEST = PRICED.map { |row| row[:cost] }.min

  # Fewest hours first, ties in cost order.
  ALL = PRICED.map { |row| new(**row, hours: hours_for(row[:cost], cheapest: CHEAPEST)) }.sort_by { |prize| [ prize.hours, prize.cost ] }.freeze

  # The free stickers (D-051): earned by the "stickers" Reward, not bought with hours, so they are not in ALL and appear
  # neither in the prize grid nor on the landing page. Only the shop's claim card shows them, for someone who has earned
  # them. An Order for them is accepted (CLAIMABLE) and costs no hours.
  STICKERS = new(key: "stickers", name: "Hack Club stickers", article: "some", kind: "Free sticker pack", cost: 0, hours: 0,
                 image: nil, icon: "sparkles-fill", url: nil,
                 facts: [ "Free for working on your game in your first hour", "Posted to the address you give" ])

  # Everything an Order can be for.
  CLAIMABLE = (ALL + [ STICKERS ]).freeze

  # The goal the landing page starts on, before you pick one.
  DEFAULT_GOAL = find("u2c")
end
