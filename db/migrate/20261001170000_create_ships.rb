class CreateShips < ActiveRecord::Migration[8.1]
  def change
    # One time someone shipped their project: what they submitted, as it was then, and where review's at.
    create_table :ships do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description, null: false
      t.string :repo_url, null: false
      t.string :demo_url, null: false
      t.json :hackatime_projects, null: false, default: []
      t.decimal :hours, precision: 6, scale: 2, null: false, default: 0
      t.string :status, null: false, default: "in_review"
      t.timestamps
    end
  end
end
