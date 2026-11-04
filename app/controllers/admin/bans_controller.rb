# Lifting a ban (D-148), for a wrongful one. An admin only, with a reason, and the audit log records it. The ban's own
# reason stays on the person (User#lift_ban!). The ship the ban rejected stays rejected.
class Admin::BansController < Admin::BaseController
  def destroy
    user = User.find(params[:user_id])
    reason = params[:reason].to_s.strip
    return redirect_to admin_user_path(user), alert: "Say why you are lifting the ban." if reason.empty?
    return redirect_to admin_user_path(user), alert: "They are not banned." unless user.banned?

    AdminAuditEvent.create!(user: current_user, tool: "lift_ban", ids: { "user_id" => user.id })
    user.lift_ban!(reason, by: current_user)
    redirect_to admin_user_path(user), notice: "Ban lifted."
  end
end
