# Every 15 minutes: the bot's nudges for everyone whose slot it is (see Nudge.deliver_due), and the pledge nudge for people with no project yet (Nudge.deliver_pledge_nudges).
class NudgeDeliveryJob < ApplicationJob
  def perform
    Nudge.deliver_due
    Nudge.deliver_pledge_nudges
  end
end
