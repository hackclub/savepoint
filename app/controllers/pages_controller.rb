class PagesController < ApplicationController
  # The landing page is Save Point's own (layouts/save_point).
  layout "save_point", only: %i[home about]

  # The landing page is for people who haven't signed in; signed in, you're back to your project (or onboarding).
  def home
    redirect_to current_user.project ? project_path : onboarding_path if signed_in?
  end

  # The same page for everyone, with no redirect: how a signed-in person reads the FAQ. Its buttons take them back to their project.
  def about
    render :home
  end
end
