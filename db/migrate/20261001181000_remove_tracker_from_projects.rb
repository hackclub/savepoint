class RemoveTrackerFromProjects < ActiveRecord::Migration[8.1]
  def change
    # Whether Hackatime's linked is the user's now (their Hackatime ID and token), not a flag on the project.
    remove_column :projects, :tracker, :string
  end
end
