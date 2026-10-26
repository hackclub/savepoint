# UTM attribution (D-043). A visit is one request to a tagged link: the five tags, the path and the time, and nothing
# that names a person (no IP address, user agent or user). A new user keeps the first tags their browser saw.
class CreateVisitsAndUtmColumns < ActiveRecord::Migration[8.1]
  TAGS = %i[utm_source utm_medium utm_campaign utm_content utm_term].freeze

  def change
    create_table :visits do |t|
      TAGS.each { |tag| t.string tag }
      t.string :path, null: false
      t.datetime :created_at, null: false
      t.index :created_at
      t.index :utm_source
    end

    TAGS.each { |tag| add_column :users, tag, :string }
  end
end
