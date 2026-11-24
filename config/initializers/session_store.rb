# The sign-in session ends after 30 days without a request. Each request that touches the session sends the cookie again with a
# new expiry, so someone who uses the site stays signed in. The key is the name Rails used before this file, so nobody is signed out.
Rails.application.config.session_store :cookie_store,
  key: "_#{Rails.application.class.module_parent_name.underscore}_session",
  # Tests run on a frozen October clock (travel_to), so a 30-day expiry set from it is long past on the real clock and Chrome drops
  # the session cookie. They get a long expiry so they do not depend on the date.
  expire_after: Rails.env.test? ? 3650.days : 30.days,
  same_site: :lax
