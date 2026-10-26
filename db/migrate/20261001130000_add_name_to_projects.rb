class AddNameToProjects < ActiveRecord::Migration[8.1]
  def change
    # What you've renamed your project to, if you have (otherwise it's your idea and tool).
    add_column :projects, :name, :string
  end
end
