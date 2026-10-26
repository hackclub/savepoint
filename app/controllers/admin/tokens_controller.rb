# Your tokens for the admin MCP server (D-046): make one, see yours, revoke one. A token is shown once, when it's made,
# with the command that adds the server to Claude. Everyone's tokens are their own: nobody sees or revokes another admin's.
class Admin::TokensController < Admin::BaseController
  def index
    @tokens = tokens
  end

  # Rendered, not redirected, so the token never travels in a flash or a session: it's on this page once and nowhere else.
  def create
    token, @token = AdminToken.generate!(user: current_user, name: params[:name])
    response.headers["Cache-Control"] = "no-store"
    @new_token = token
    @tokens = tokens
    render :index
  rescue ActiveRecord::RecordInvalid => error
    @tokens = tokens
    @error = error.record.errors.full_messages.first
    render :index, status: :unprocessable_entity
  end

  def destroy
    current_user.admin_tokens.find(params[:id]).revoke!
    redirect_to admin_tokens_path
  end

  private
    def tokens = current_user.admin_tokens.order(created_at: :desc, id: :desc)
end
