class OnboardingController < ApplicationController
  # Save Point's own layout and style sheet (D-009).
  layout "save_point"

  # Opening the sheet is step 1, recorded here and not by the page's script, so someone who leaves before any script ran still counts.
  def show
    record_step(1) if current_user
  end

  # Step 2's rows again, for the code link typed in step 1 (D-064): a Hackatime project linked to a different repo goes last,
  # with a warning. The project isn't saved until the end, so the page sends the repo. 204 when there are no rows to show.
  def hackatime
    return head :unauthorized unless current_user

    hackatime = helpers.onboarding_hackatime(current_user, repo: params[:repo].to_s)
    return head :no_content unless hackatime[:state] == :ready && hackatime[:projects].any?

    render partial: "onboarding/hackatime_rows", locals: { user: current_user, hackatime: }
  end

  # How far you got: the page reports each step it reaches (5 is Start building). Only a step beyond the stored one is kept,
  # so going back or reloading never lowers it. A beacon: anything odd is ignored, and it never answers with an error.
  def progress
    return head :unauthorized unless current_user

    step = Integer(params[:step].to_s, 10, exception: false)
    record_step(step) if step&.between?(1, 5)
    head :no_content
  end

  private
    def record_step(step)
      return unless step > current_user.onboarding_step_reached.to_i

      current_user.update_columns(onboarding_step_reached: step, onboarding_step_at: Time.current)
    end
end
