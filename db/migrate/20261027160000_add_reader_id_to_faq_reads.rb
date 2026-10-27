# FAQ reads count people (D-095). A random ID the browser makes once and keeps in localStorage tells readers apart. It is
# linked to no user, cookie or IP address. Reads from before this have none.
class AddReaderIdToFaqReads < ActiveRecord::Migration[8.1]
  def change
    add_column :faq_reads, :reader_id, :string
    add_index :faq_reads, :reader_id
  end
end
