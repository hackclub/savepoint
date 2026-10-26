# A pomodoro with your buddy, for the pomodoro screen (JSON): start one, check on it (who's in, how long's left), or
# join the one your buddy started.
class BuddyPomodorosController < ApplicationController
  before_action :require_pair

  def show
    render json: status_of(@pair.live_pomodoro)
  end

  def create
    pomodoro = @pair.live_pomodoro
    unless pomodoro
      pomodoro = @pair.pomodoros.create!(started_by: @project, minutes: params.expect(:minutes).to_i,
                                         started_at: Time.current)
    end

    render json: status_of(pomodoro), status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: error.record.errors.full_messages.first }, status: :unprocessable_entity
  end

  def join
    pomodoro = @pair.live_pomodoro
    return render json: status_of(nil), status: :not_found unless pomodoro

    if pomodoro.started_by != @project && pomodoro.joined_at.nil?
      pomodoro.update!(joined_at: Time.current)
    end

    render json: status_of(pomodoro)
  end

  private
    def require_pair
      @project = current_user&.project
      @pair = @project&.pair
      head :not_found unless @pair
    end

    def status_of(pomodoro)
      buddy = @pair.buddy_of(@project)
      buddy_name = buddy.user.public_name
      return { live: false, buddy: buddy_name } unless pomodoro

      { live: true, buddy: buddy_name, minutes: pomodoro.minutes, ends_at: pomodoro.ends_at.iso8601(3),
        now: Time.current.iso8601(3), mine: pomodoro.started_by == @project, you_in: pomodoro.in?(@project),
        buddy_in: pomodoro.in?(buddy) }
    end
end
