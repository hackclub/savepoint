class AddSetupStepsToProjects < ActiveRecord::Migration[8.1]
  def change
    # Which Hackatime projects this build is, and the setup steps you can put off (the repo) or skip (posting your idea).
    add_column :projects, :hackatime_projects, :json, null: false, default: []
    add_column :projects, :repo_later, :boolean, null: false, default: false
    add_column :projects, :idea_skipped, :boolean, null: false, default: false
    # Whether your game's in the queue to be played live at the play party.
    add_column :projects, :party_queued, :boolean, null: false, default: false
  end
end
