class AddHoursStartOverrideToProjects < ActiveRecord::Migration[8.1]
  # D-065: a reviewer's start for the project's hours, in place of the later of Save Point's start and the sign-up.
  def change
    add_column :projects, :hours_start_override, :datetime
  end
end
