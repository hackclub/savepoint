# FAQ read time (D-094). A read is one stay with a question open: the question's key (Faq), the whole seconds it was open
# and the time. Nothing that names a person: no user, IP address, user agent or session.
class CreateFaqReads < ActiveRecord::Migration[8.1]
  def change
    create_table :faq_reads do |t|
      t.string :key, null: false
      t.integer :seconds, null: false
      t.datetime :created_at, null: false
      t.index %i[key created_at]
    end
  end
end
