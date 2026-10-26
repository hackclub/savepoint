# How far a participant got through /start (OnboardingController#progress): the furthest step reached (1 to 5, where 5
# means they pressed Start building) and when it was last moved forward.
class AddOnboardingProgressToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :onboarding_step_reached, :integer
    add_column :users, :onboarding_step_at, :datetime
  end
end
