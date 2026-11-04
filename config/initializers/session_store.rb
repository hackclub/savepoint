# The sign-in session ends after 30 days without a request. Each request that touches the session sends the cookie again with a
# new expiry, so someone who uses the site stays signed in. The key is the name Rails used before this file, so nobody is signed out.
Rails.application.config.session_store :cookie_store,
  key: "_#{Rails.application.class.module_parent_name.underscore}_session",
  expire_after: 30.days,
  same_site: :lax
