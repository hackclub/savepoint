# D-066: brings one project's jame gam submission time up to date, and rebuilds the person's days when it moved.
class JameGamRefreshJob < ApplicationJob
  def perform(project_id)
    Project.find_by(id: project_id)&.refresh_jame_gam!
  end
end
