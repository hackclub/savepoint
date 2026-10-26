class AddTheseusLetterIdToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :theseus_letter_id, :string
  end
end
