# Everyone who's asked for more time to ship (Extension): waiting first, oldest at the top, then decided. Approve or
# deny here; the bot tells them either way (ExtensionNotifier).
class Admin::ExtensionsController < Admin::BaseController
  def index
    @pending = Extension.pending.includes(project: :user).order(:created_at)
    @decided = Extension.decided.includes(:decided_by, project: :user).order(decided_at: :desc)
  end

  def update
    extension = Extension.find(params[:id])
    decided = extension.decide!(params[:decision].to_s, by: current_user)
    redirect_to admin_extensions_path, alert: ("That one's been decided already." unless decided)
  end
end
