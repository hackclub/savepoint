# The NPS form (NpsResponse): on a page of its own, from the footer's Feedback link and from the ship page, which
# sends you here when you are due and brings you back. The project page opens the same form in a popup. An answer
# from the ship page is a "ship" answer, linked to the project; any other is "daily".
class NpsResponsesController < ApplicationController
  layout "save_point"
  before_action :require_participant

  def show
    @nps = NpsResponse.new
    @for_ship = params[:ship].present? && current_user.project.present?
  end

  def create
    @for_ship = params[:ship].present? && current_user.project.present?
    @nps = NpsResponse.new(params.fetch(:nps_response, {}).permit(*NpsResponse::FIELDS)
                                 .merge(user: current_user, source: @for_ship ? "ship" : "daily", project: (current_user.project if @for_ship)))
    if @nps.save
      redirect_to(@for_ship ? project_ship_path : params[:back] == "project" ? project_path : nps_path, status: :see_other,
                  notice: "Thanks!")
    elsif params[:back] == "project"
      redirect_to project_path, status: :see_other, alert: "Pick a number and fill in the * ones first."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def require_participant
      redirect_to root_path unless NpsResponse.participant?(current_user)
    end
end
