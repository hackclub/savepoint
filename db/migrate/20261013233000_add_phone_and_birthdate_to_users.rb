class AddPhoneAndBirthdateToUsers < ActiveRecord::Migration[8.1]
  def change
    # From Hack Club Auth's phone and birthdate scopes, kept encrypted, for a ship's submission.
    add_column :users, :phone_number, :text
    add_column :users, :birthdate, :text
  end
end
