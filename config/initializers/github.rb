# GitHub API auth: see lib/github_auth.rb. The ship page's commit list and README check use it.
# Set GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID and GITHUB_APP_PRIVATE_KEY (or _PATH) for a GitHub App (an Orchard
# env var in production), or GITHUB_TOKEN / credentials github.token for a token.
require Rails.root.join("lib/github_auth")

if Rails.env.production? && !GithubAuth.app_configured? && GithubAuth.authorization(cache: ActiveSupport::Cache::NullStore.new).nil?
  Rails.logger.warn("GitHub auth missing (GITHUB_APP_* or GITHUB_TOKEN): GitHub API calls are unauthenticated and limited to 60 an hour per IP")
end
