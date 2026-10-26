# The admin MCP server (D-046, AdminMcp): MCP's Streamable HTTP, stateless. Each POST carries one JSON-RPC message and gets
# one JSON answer. There is no session and no event stream, so GET and DELETE answer 405.
#
# | Request | Answer |
# |---|---|
# | No token, an unknown or revoked one, or one whose owner isn't an admin any more | 404, as the admin pages answer |
# | More than REQUESTS_PER_MINUTE with one token | 429 |
# | A good token | The MCP answer, with that admin's tools |
#
# The session cookie does nothing here: this is not an Admin::BaseController, and a browser can't add the Authorization
# header to a cross-site request, so the path needs no CSRF check.
class Admin::McpController < ActionController::API
  REQUESTS_PER_MINUTE = 240
  MAX_BODY = 1.megabyte

  before_action :authenticate
  before_action :limit_rate

  def create
    return render_error(413, "Too large.") if request.content_length.to_i > MAX_BODY

    answer = AdminMcp.server(@caller).handle_json(request.raw_post)
    # A notification has no answer.
    answer ? render(json: answer) : head(:accepted)
  end

  def unsupported
    head :method_not_allowed, allow: "POST"
  end

  private
    def authenticate
      token = AdminToken.authenticate(request.authorization.to_s[/\ABearer +(\S+)\s*\z/i, 1])
      return head(:not_found) unless token&.user&.admin?

      token.used!
      @caller = AdminMcp::Caller.new(user: token.user, token:)
    end

    # A fixed one-minute window per token, in the cache.
    def limit_rate
      key = "admin_mcp/#{@caller.token.id}/#{Time.current.to_i / 60}"
      count = Rails.cache.increment(key, 1, expires_in: 2.minutes) || (Rails.cache.write(key, 1, expires_in: 2.minutes) && 1)
      return if count.to_i <= REQUESTS_PER_MINUTE

      response.headers["Retry-After"] = "60"
      render_error(429, "Too many requests with this token. Wait a minute.")
    end

    def render_error(status, message)
      render json: { jsonrpc: "2.0", error: { code: -32_000, message: }, id: nil }, status:
    end
end
