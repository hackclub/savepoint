# One answer to the NPS form (NpsResponse): a score from 0 to 10 and what the participant wrote. A ship's answer
# is linked to the project, and a project that goes leaves the answer standing.
class CreateNpsResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :nps_responses do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :project, foreign_key: { on_delete: :nullify }
      t.string :source, null: false
      t.integer :score, null: false
      t.text :doing_well
      t.text :improve
      t.text :anything_else
      t.timestamps
      t.index %i[user_id created_at]
      t.index :created_at
      t.check_constraint "score >= 0 AND score <= 10", name: "nps_responses_score_0_to_10"
    end
  end
end
