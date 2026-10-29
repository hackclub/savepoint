ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Nothing asks for the NPS (no popup, and a ship needs no answer) unless a test of it turns asking on.
    setup { NpsResponse.asking = false }

    # Add more helper methods to be used by all tests here...
  end
end

# Signing in with Hack Club Auth goes straight to the callback with this user instead of leaving the app, and
# nothing asks the real Hack Club Auth who's there.
OmniAuth.config.test_mode = true
Rails.application.config.x.hack_club_auth_whoami_url = nil

# Nobody asks the real Hackatime either: who each token belongs to, the projects each Hackatime user has
# logged time on, and when they were building (none of the time, unless a test says otherwise).
Hackatime.stubbed_users = { "token-orpheus" => "1001", "token-heidi" => "1002" }
Hackatime.stubbed_projects = {
  "1001" => [ Hackatime::Project.new("rhythm-game", 5400), Hackatime::Project.new("beat-sheet-art", 900),
              Hackatime::Project.new("dotfiles", 11_160) ],
  "1002" => [ Hackatime::Project.new("heidis-game", 600) ]
}
Hackatime.stubbed_spans = {}
Hackatime.stubbed_category_seconds = {}
Hackatime.stubbed_trust_levels = {} # nobody is banned unless a test says so
Hackatime.stubbed_repo_urls = {} # no project has a repo link on Hackatime unless a test says so

module HackClubAuthHelpers
  def mock_hack_club_auth(uid: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi",
                          slack_id: "U0HEIDI", verification_status: "verified", ysws_eligible: true, address: HQ_ADDRESS,
                          phone_number: "+18025550123", birthdate: "2010-04-01")
    OmniAuth.config.mock_auth[:hackclub] = OmniAuth::AuthHash.new(
      provider: "hackclub", uid:,
      info: { email:, name:, first_name: },
      extra: { raw_info: { sub: uid, email:, name:, slack_id:, verification_status:, ysws_eligible:, address:, phone_number:, birthdate: }.compact }
    )
  end

  HQ_ADDRESS = { "street_address" => "15 Falls Rd", "locality" => "Shelburne", "region" => "VT", "postal_code" => "05482",
                 "country" => "US" }.freeze
end

module HackatimeHelpers
  # Linking Hackatime goes straight to the callback with this token.
  def mock_hackatime(token: "token-orpheus")
    OmniAuth.config.mock_auth[:hackatime] = OmniAuth::AuthHash.new(provider: "hackatime", uid: nil, credentials: { token: })
  end

  # As if they'd already linked Hackatime.
  # A review's approval, then a fraud check that passes: the ship is approved, with hours to spend (D-063).
  def approve_through_fraud(ship, technical_features: "A beat grid and a combo meter.", **options)
    ship.decide!("approved", by: users(:ana), technical_features:, **options)
    ship.pass_fraud!(by: users(:ana))
    ship
  end

  def link_hackatime(user, token: "token-#{user.first_name.downcase}")
    user.update!(hackatime_uid: Hackatime.stubbed_users.fetch(token), hackatime_access_token: token)
  end

  # A span of `minutes` starting at `at`, as Hackatime sends it.
  def hackatime_span(at, minutes)
    { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }
  end

  # Hackatime answers `body` (JSON) to its next requests, for the block, with an API key already in hand: for the tests
  # that read what a real stats answer carries. Every singleton it swaps goes back in `ensure`.
  def with_hackatime_answer(body)
    answer = Net::HTTPSuccess.new("1.1", "200", "OK").tap { |response| response.define_singleton_method(:body) { body } }
    originals = %i[get api_key].to_h { |name| [ name, Hackatime.method(name) ] }
    Hackatime.define_singleton_method(:get) { |*, **| answer }
    Hackatime.define_singleton_method(:api_key) { |*| "key" }
    yield
  ensure
    originals&.each { |name, original| Hackatime.define_singleton_method(name, original) }
  end

  # Save Point has no play party date yet, so Program::PLAY_PARTY_ON is the old day. Set it for the block.
  def with_play_party_on(date)
    original = Program::PLAY_PARTY_ON
    silence_warnings { Program.const_set(:PLAY_PARTY_ON, date) }
    yield
  ensure
    silence_warnings { Program.const_set(:PLAY_PARTY_ON, original) }
  end

  # What Hackatime says Orpheus built, for the block: `hours` of it, on Save Point's first day (so every number of
  # hours has it). The block runs on the day after, so that day's over whatever the time is now.
  def with_hackatime_hours(hours, uid: "1001")
    before = Hackatime.stubbed_spans
    Hackatime.stubbed_spans = before.merge(uid => [ hackatime_span(Program::STARTS_AT, (hours * 60).round) ])
    travel_to(Time.utc(2026, 10, 24, 12)) { yield }
  ensure
    Hackatime.stubbed_spans = before
  end
end

module ShopHelpers
  # As if every pick took this many hours (Project#hours_needed), for the schedule tests, whose arithmetic is about
  # days, not prices.
  def with_hours_needed(hours)
    Project.class_eval do
      alias_method :hours_needed_without_test, :hours_needed
      define_method(:hours_needed) { hours }
    end
    yield
  ensure
    Project.class_eval do
      alias_method :hours_needed, :hours_needed_without_test
      remove_method :hours_needed_without_test
    end
  end
end

module ShipHelpers
  # D-111: the columns of an approved ship as the fraud check leaves them: the review's hours are the approved hours and
  # nothing is deducted. The database refuses an approved ship whose hours don't add up, so a test that skips the review writes these.
  def approved_columns(hours, **more) = { status: "approved", fraud_status: "passed", review_hours: hours, approved_hours: hours }.merge(more)
end

ActiveSupport::TestCase.include ShipHelpers
ActiveSupport::TestCase.include ShopHelpers
ActiveSupport::TestCase.include HackClubAuthHelpers
ActiveSupport::TestCase.include HackatimeHelpers
