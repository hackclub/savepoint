require "active_support/testing/time_helpers"

# Development only: pretend it's a given Save Point day. /dev stores the moment in the session and every request runs
# inside travel_to, so Time.current, Date.current and Program.day all agree. ApplicationController includes this only in
# development, and each method refuses to do anything anywhere else, so production and test never travel.
module DevClock
  extend ActiveSupport::Concern

  # What /dev offers: "day 1" to "day 10", before the start, and after the end.
  def self.options
    days = (1..Program.day(Program::ENDS_AT - 1)[:total]).map { |number| [ "Day #{number}", Program::STARTS_AT + (number - 1).days + 12.hours ] }
    [ [ "Before the start", Program::STARTS_AT - 1.day ] ] + days + [ [ "After the end", Program::ENDS_AT + 1.hour ] ]
  end

  included do
    include ActiveSupport::Testing::TimeHelpers
    around_action :dev_clock
  end

  private
    def dev_clock(&block)
      moment = Rails.env.development? && session[:dev_now].presence && Time.zone.parse(session[:dev_now])
      moment ? travel_to(moment, &block) : yield
    end
end
