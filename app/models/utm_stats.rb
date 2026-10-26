# Where sign-ups come from, in the admin home's sign-ups section (D-043): per source, medium and campaign, the tagged visits, the
# sign-ups and sign-ups per visit. Only landing-page visits (path "/") count, because every page view is a Visit since
# D-047 and the rest are people already signed in (D-058). Visits and sign-ups without tags are one more row. Admins'
# sign-ups are left out (D-032).
class UtmStats
  GROUP = %w[utm_source utm_medium utm_campaign].freeze
  Row = Data.define(:source, :medium, :campaign, :visits, :signups) do
    def rate = visits.zero? ? nil : 100.0 * signups / visits
  end

  def initialize
    landing = Visit.where(path: "/")
    @visits = landing.where.not(**tag_nils(Visit::TAGS)).group(*GROUP).count # any of the five tags set (NAND)
    @untagged_visits = landing.where(**tag_nils(Visit::TAGS)).count
    @signups = User.participants.where.not(**tag_nils(Visit::TAGS)).group(*GROUP).count
    @untagged = User.participants.where(**tag_nils(Visit::TAGS)).count
  end

  # Most sign-ups first, then most visits.
  def rows
    (@visits.keys | @signups.keys).map { |key| Row.new(*key, @visits.fetch(key, 0), @signups.fetch(key, 0)) }
      .sort_by { [ -it.signups, -it.visits, it.source.to_s ] }
  end

  # Sign-ups, and landing visits, that came with no tags at all (all five nil).
  attr_reader :untagged, :untagged_visits

  def untagged_rate = untagged_visits.zero? ? nil : 100.0 * untagged / untagged_visits

  def any? = @visits.any? || @signups.any? || @untagged.positive? || @untagged_visits.positive?

  private
    def tag_nils(tags) = tags.index_with(nil)
end
