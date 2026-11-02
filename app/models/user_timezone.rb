# A stored user timezone, made safe to use. Old browsers and devices report legacy IANA names (Asia/Calcutta), and a
# server tzdata without those aliases raises on them. Legacy names map to their canonical ones, and anything that
# isn't a real timezone falls back to UTC instead of raising.
module UserTimezone
  LEGACY = {
    "Asia/Calcutta" => "Asia/Kolkata",
    "Asia/Katmandu" => "Asia/Kathmandu",
    "America/Buenos_Aires" => "America/Argentina/Buenos_Aires",
    "Asia/Saigon" => "Asia/Ho_Chi_Minh",
    "Asia/Rangoon" => "Asia/Yangon",
    "Europe/Kiev" => "Europe/Kyiv"
  }.freeze

  class << self
    def name(raw)
      candidate = LEGACY.fetch(raw.to_s.strip, raw.to_s.strip)
      return "UTC" if candidate.empty?
      TZInfo::Timezone.get(candidate).identifier
    rescue TZInfo::InvalidTimezoneIdentifier, ArgumentError
      "UTC"
    end

    def zone(raw) = ActiveSupport::TimeZone[name(raw)] || ActiveSupport::TimeZone["UTC"]
  end
end
