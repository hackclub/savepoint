# The Lapse sessions behind a ship's art time, for the reviewer (D-063, D-042). Lapse sends each timelapse to Hackatime
# as heartbeats with language "Lapse" and entity "<title> (<timelapse id>)". Hackatime's admin API lists those heartbeats
# per project, and Lapse's public API describes each timelapse. The admin API needs HACKATIME_ADMIN_API_KEY: without it
# nothing is guessed, and the result says the list is unavailable. Never raises.
class Ship::Lapses
  LAPSE_API = "https://api.lapse.hackclub.com/api"
  PAGE = 5000
  ID_IN_ENTITY = /\(([A-Za-z0-9_-]{6,64})\)\s*\z/

  Lapse = Data.define(:id, :title, :duration, :project, :url)
  Result = Data.define(:lapses, :error) do
    def seconds = lapses.sum(&:duration)
  end

  def self.key = ENV["HACKATIME_ADMIN_API_KEY"].presence
  def self.configured? = key.present?
  def self.admin_url = "#{Rails.configuration.x.hackatime_url}/api/admin/v1"

  def self.for(ship) = new(ship.project.user, ship.hackatime_projects, ship.project.hours_start..ship.created_at).fetch

  def initialize(user, projects, window)
    @user = user
    @projects = projects
    @window = window
  end

  def fetch
    return Result.new(lapses: [], error: "Hackatime's admin API key isn't set") unless self.class.configured?
    return Result.new(lapses: [], error: "They haven't linked Hackatime") if @user.hackatime_uid.blank?

    found = @projects.flat_map { |project| lapse_ids(project).map { [ it, project ] } }.uniq(&:first)
    Result.new(lapses: found.filter_map { |id, project| describe(id, project) }, error: nil)
  rescue Web::Error, JSON::ParserError
    Result.new(lapses: [], error: "Lapse or Hackatime couldn't be reached. Try again in a minute.")
  end

  private
    # Distinct timelapse ids in the entities of one project's Lapse heartbeats inside the window. The admin API takes
    # epoch seconds for both ends and includes both.
    def lapse_ids(project)
      ids = []
      offset = 0
      loop do
        query = { user_id: @user.hackatime_uid, project:, language: "Lapse", limit: PAGE, offset:,
                  start_date: @window.begin.to_i, end_date: @window.end.to_i }.to_query
        response = Web.get("#{self.class.admin_url}/user/heartbeats?#{query}", headers: { "Authorization" => "Bearer #{self.class.key}" }, timeout: 20)
        raise Web::Error, "Hackatime answered #{response.status}" unless response.ok?

        body = response.json
        ids.concat(Array(body["heartbeats"]).filter_map { it["entity"].to_s[ID_IN_ENTITY, 1] })
        break unless body["has_more"]

        offset += PAGE
      end
      ids.uniq
    end

    # The public view of one timelapse. One that failed processing has no video to review, so it is left out.
    def describe(id, project)
      response = Web.get("#{LAPSE_API}/timelapse/query?#{{ id: }.to_query}")
      return if response.status == 404
      raise Web::Error, "Lapse answered #{response.status}" unless response.ok?

      timelapse = response.json.dig("data", "timelapse")
      return if timelapse.nil? || timelapse["visibility"] == "FAILED_PROCESSING"

      Lapse.new(id:, title: timelapse["name"].to_s, duration: timelapse["duration"].to_i, project:,
                url: "https://lapse.hackclub.com/timelapse/#{id}")
    end
end
