class AddJameGamSubmissionToProjects < ActiveRecord::Migration[8.1]
  # D-066: the latest jame gam submission that matches the project (its Airtable record id and review status are for the review page).
  def change
    add_column :projects, :jame_gam_submitted_at, :datetime
    add_column :projects, :jame_gam_submission_id, :string
    add_column :projects, :jame_gam_review_status, :string
  end
end
