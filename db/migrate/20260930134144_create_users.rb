class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :hca_id, null: false
      t.string :email
      t.string :name
      t.string :slack_id
      t.string :verification_status
      t.boolean :ysws_eligible, null: false, default: false

      t.timestamps
    end
    add_index :users, :hca_id, unique: true
  end
end
