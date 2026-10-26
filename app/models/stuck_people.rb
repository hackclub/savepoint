# The participants who stopped, grouped by how far they got (D-078 item 1). Names people, so it lives on the admin home and not in
# the analytics service (D-047). Admins are left out (D-032), and so are banned accounts, people who have shipped, and anyone
# still building. Read from the app's own columns: the project, its picked Hackatime projects, the synced streak days and
# last_seen_*. Groups come most actionable first: someone who coded and went quiet is the nearest to coming back.
class StuckPeople
  LIMIT = 50

  Group = Data.define(:key, :label, :about, :people, :total)
  Person = Data.define(:user, :signed_up_at, :last_seen_at, :last_path)

  GROUPS = [
    [ :quiet, "Coded, then nothing in 48 hours", "built some time, none in the last 48 hours" ],
    [ :no_time, "Picked a project, no time yet", "picked their Hackatime project, but none of it has been coded" ],
    [ :not_picked, "Pledged, not picked", "pledged, but haven't picked a Hackatime project" ],
    [ :no_pledge, "Linked Hackatime, no pledge", "linked Hackatime, but haven't pledged a project" ],
    [ :signed_in, "Signed in only", "signed in, nothing else" ]
  ].freeze

  def initialize(now: Time.current)
    @now = now
  end

  # Each group with up to LIMIT people, the most recently seen first, and how many in all. Empty groups are kept, so the
  # admin sees there's nobody.
  def groups
    sorted = people.group_by { |user| group_of(user) }
    GROUPS.map do |key, label, about|
      users = sorted.fetch(key, []).sort_by { [ -(it.last_seen_at || it.created_at).to_i, it.id ] }
      Group.new(key:, label:, about:, total: users.size, people: users.first(LIMIT).map { person(it) })
    end
  end

  private
    def people
      @people ||= User.participants.where(banned_at: nil).includes(:project).where.not(id: shipped_user_ids).to_a
    end

    def shipped_user_ids = Ship.joins(:project).select("projects.user_id")

    def group_of(user)
      project = user.project
      if project.nil? then user.hackatime_linked? ? :no_pledge : :signed_in
      elsif project.hackatime_projects.blank? then :not_picked
      elsif !coded.key?(user.id) then :no_time
      elsif coded[user.id] < @now.to_date - 1 then :quiet # not today or yesterday: 48 hours, by calendar days
      end
    end

    # The newest day each person coded any time (the streak days Hackatime synced), by user.
    def coded
      @coded ||= StreakActivity.where(user_id: people.map(&:id), coded_seconds: 1..).group(:user_id).maximum(:activity_date)
    end

    def person(user)
      Person.new(user:, signed_up_at: user.created_at, last_seen_at: user.last_seen_at, last_path: user.last_seen_path)
    end
end
