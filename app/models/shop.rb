# The shop's money: hours you log turn into dollars to spend on a prize. FIRST_RATE an hour for your first
# FIRST_HOURS, RATE an hour after that. A prize costs what its maker charges (Prize#cost), so the hours it takes are its price run back through the rates. The rates and prices stay here: the shop
# only ever shows hours.
module Shop
  FIRST_HOURS = Program::HOURS_PER_REWARD
  FIRST_RATE = 5
  RATE = 4

  # Dollars for hours logged, to the cent.
  def self.dollars(hours)
    hours = hours.to_f
    ([ hours, FIRST_HOURS ].min * FIRST_RATE + [ hours - FIRST_HOURS, 0 ].max * RATE).round(2)
  end

  # Hours that earn these dollars: always a whole number, always rounded up, so nothing's ever 7.4 hours and a
  # part hour is a whole one of building. (Rounded to a thousandth first, so 12.000000001 is 12, not 13.)
  def self.hours_for(dollars)
    dollars = dollars.to_f
    first = FIRST_HOURS * FIRST_RATE
    hours = dollars <= first ? dollars / FIRST_RATE : FIRST_HOURS + (dollars - first) / RATE
    hours.round(3).ceil
  end
end
