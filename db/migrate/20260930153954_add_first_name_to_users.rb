class AddFirstNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :first_name, :string
  end
end
