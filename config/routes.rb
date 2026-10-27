Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
  get "about" => "pages#about", as: :about # the landing page and its FAQ, for signed-in people too
  get "start" => "onboarding#show", as: :onboarding
  get "start/hackatime" => "onboarding#hackatime", as: :onboarding_hackatime
  post "start/progress" => "onboarding#progress", as: :onboarding_progress
  resource :project, only: %i[show create update] do
    resource :ship, only: %i[show create] do
      patch :hackatime # tick or untick a Hackatime project on the ship page
    end
    resource :extension, only: :create
    resource :goal_seen, only: :create # the earned-it popup was shown for this goal
    get :hours
    get :first_heartbeat # has your first time reached Hackatime yet (the project page waits for it)
    resource :streak, only: :update
  end
  # How likely you are to recommend Save Point, asked at ship and every so often (NpsResponse).
  resource :nps, only: %i[show create], controller: "nps_responses"
  resource :leaderboard, only: :show
  # The prizes you can claim with approved hours.
  resource :shop, only: :show, controller: "shop" do
    # Claiming your pick with your approved hours.
    resource :order, only: :create
  end
  # Save Point in numbers, for anyone: totals only, never anyone on their own (PublicStats).
  get "stats" => "stats#show", as: :stats
  # How many people have signed up, for the landing page's counter: the number and nothing else.
  get "signups" => "signups#show", as: :signups, defaults: { format: :json }
  # How long an FAQ question was open (FaqRead, D-094): a beacon from the landing page, with nothing about the reader.
  post "faq_reads" => "faq_reads#create", as: :faq_reads
  resource :buddy, only: :show do
    # A pomodoro together: start one, see how it's going (polled), and join your buddy's.
    resource :pomodoro, only: %i[show create], controller: "buddy_pomodoros" do
      post :join
    end
  end
  # Someone's buddy invite: see who wants to build with you, and accept.
  get "b/:code" => "buddy_invites#show", as: :buddy_invite
  post "b/:code" => "buddy_invites#accept"

  # The links in the bot's messages: the button (tracked, then on to where it says), and stopping its messages.
  get "n/:token" => "nudge_links#show", as: :nudge_link
  get "n/:token/stop" => "nudge_links#stop", as: :nudge_stop
  post "n/:token/stop" => "nudge_links#mute"
  delete "n/:token/stop" => "nudge_links#unmute"

  # Slack's reply-to-a-click for the bot's messages: the link buttons in announcements. It only says OK.
  post "slack/interactions" => "slack_interactions#create", as: :slack_interactions

  # How the bot's nudges are doing, and what the bandit's learned, Save Point's numbers day by day, everyone who's
  # signed in, with seeing the site as any of them, who's asked for more time to ship, and every ship in full, to
  # approve or send back, and the tokens for the MCP server. Admins only.
  namespace :admin do
    # Every admin page, and what's waiting on an admin.
    root "home#show"
    resources :nudges, only: :index
    # Stats and Numbers are sections of the admin home now (D-073), so their old URLs go to the section.
    get "stats", to: redirect("/admin#growth", status: 301)
    get "metrics", to: redirect("/admin#history", status: 301)
    # The home's heavy sections, each in a lazy Turbo Frame so the first paint doesn't wait for them.
    get "growth" => "home#growth", as: :growth
    get "signups" => "home#signups", as: :signups
    get "stuck" => "home#stuck", as: :stuck
    get "history" => "home#history", as: :history
    resources :extensions, only: %i[index update]
    resources :orders, only: %i[index update] do
      post :send_stickers, on: :collection
    end
    # The review queue and the fraud queue open the oldest ship waiting (D-063). The page keeps its claim alive on a beat.
    get "review" => "queues#review"
    get "fraud" => "queues#fraud"
    post "claims/heartbeat" => "claims#heartbeat"
    resources :ships, only: %i[index show] do
      member do
        patch :checklist
        patch :snapshot
        patch :hours_start
        patch :lapse_split
        patch :reviewer_ai
        post :review
        post :fraud
        post :send_back
      end
      # The screenshots of the snapshot editor (Ship::Snapshot), answered in JSON.
      resources :screenshots, controller: "ship_screenshots", only: %i[create destroy] do
        patch :order, on: :collection
      end
    end
    resources :projects, only: %i[index show]
    resources :users, only: %i[index show] do
      resource :impersonation, only: :create
    end
    # The admin MCP server (D-046), for Claude: POST only, with an admin's token rather than the session (Admin::McpController).
    post "mcp" => "mcp#create", as: :mcp
    match "mcp" => "mcp#unsupported", via: %i[get delete]
    resources :tokens, only: %i[index create destroy]
    # Stopping has to work while you're someone who isn't an admin.
    resource :impersonation, only: :destroy
  end

  # Development only: the fake people from bin/rails dev:fake. Never mounted anywhere else.
  if Rails.env.development?
    get "dev" => "dev/fakes#index", as: :dev
    post "dev/buddy" => "dev/fakes#buddy", as: :dev_buddy
    post "dev/clock" => "dev/fakes#clock", as: :dev_clock
    post "dev/hours" => "dev/fakes#hours", as: :dev_hours
    post "dev/orders/reset" => "dev/fakes#reset_orders", as: :dev_reset_orders
    post "dev/goal_popup/reset" => "dev/fakes#reset_goal_popup", as: :dev_reset_goal_popup
    post "dev/take_over/:id" => "dev/fakes#take_over", as: :dev_take_over
    post "dev/stickers/fresh" => "dev/fakes#sticker_fresh", as: :dev_sticker_fresh
    post "dev/stickers/minutes" => "dev/fakes#sticker_minutes", as: :dev_sticker_minutes
    post "dev/stickers/eligible" => "dev/fakes#sticker_eligible", as: :dev_sticker_eligible
    post "dev/stickers/ban" => "dev/fakes#sticker_ban", as: :dev_sticker_ban
  end

  # Hack Club Auth. Signing in is a POST to /auth/hackclub (OmniAuth's middleware), which comes back here.
  # Linking Hackatime comes back here; it doesn't sign you in.
  get "auth/hackatime/callback" => "hackatime_links#create", as: :hackatime_link_callback
  get "auth/:provider/callback" => "sessions#create", as: :auth_callback
  get "auth/failure" => "sessions#failure", as: :auth_failure
  # Straight after sign-in, when there's no Hackatime token yet (D-026). It posts itself on to Hackatime's OAuth.
  get "sign-in/hackatime" => "sessions#hackatime_step", as: :sign_in_hackatime
  delete "logout" => "sessions#destroy", as: :logout
end
