class AddHackatimeAutoLinkToProjects < ActiveRecord::Migration[8.1]
  def change
    # The Hackatime projects you already had when we first looked after you linked Hackatime (nil until we've looked):
    # the first new one after that links itself.
    add_column :projects, :hackatime_baseline, :json
    # Whether your linked Hackatime project was linked for you, and you haven't kept or changed it yet.
    add_column :projects, :hackatime_auto_linked, :boolean, default: false, null: false
  end
end
