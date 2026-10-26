class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      # The pledge, as signed at the end of onboarding.
      t.string :tool, null: false
      t.string :tool_name, null: false
      t.string :idea, null: false
      t.string :prize, null: false
      t.integer :pace_minutes, null: false
      t.string :build_time, null: false
      t.date :signed_on, null: false

      # Setup, on the project page.
      t.string :tracker
      t.boolean :slack_joined, null: false, default: false
      t.string :repo_url
      t.boolean :idea_posted, null: false, default: false

      t.timestamps
    end
  end
end
