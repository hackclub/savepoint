# Content security policy, in REPORT-ONLY mode: browsers log each violation in the console and block nothing. The layouts hold an
# inline script (application.html.erb) and many inline styles, so enforcing before a pass over the console could break pages.
# Once the console is clean on the main pages, remove the report-only line below. There is no report endpoint yet.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data, :blob
    policy.object_src  :none
    policy.base_uri    :self
    policy.frame_ancestors :self
    policy.form_action :self, :https
    policy.script_src  :self, :https
    policy.style_src   :self, :https, :unsafe_inline
    policy.connect_src :self, :https
  end

  # A new nonce for each response (not the session id, which would start a session for every visitor).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  config.content_security_policy_report_only = true
end
