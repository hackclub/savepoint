class RemoveSlackAndIdeaStepsFromProjects < ActiveRecord::Migration[8.1]
  def change
    # Everyone's added to #wrong for them, and ideas come from onboarding: neither is a setup step any more.
    remove_column :projects, :slack_joined, :boolean, default: false, null: false
    remove_column :projects, :idea_posted, :boolean, default: false, null: false
    remove_column :projects, :idea_skipped, :boolean, default: false, null: false
  end
end
