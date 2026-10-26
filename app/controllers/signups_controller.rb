# The number of people signed up, for the landing page to poll. Public, and only ever the number.
class SignupsController < ApplicationController
  def show
    expires_in 15.seconds, public: true
    render json: { count: User.participant_count }
  end
end
