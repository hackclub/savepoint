# The NPS on the admin home: how likely participants are to recommend Save Point, from their answers in the
# popup and at ship. NPS is the share of promoters, who answer 9 or 10, minus the share of detractors, who answer 0
# to 6, as a whole number from -100 to 100. Passives, 7 or 8, count only toward the people. Over 7 days each person
# counts once, by their latest answer in it. Days are UTC, as in Metric. Admins' answers are left out.
class NpsStats
  Span = Data.define(:last_day, :promoters, :passives, :detractors) do
    def people = promoters + passives + detractors
    def nps = people.zero? ? nil : (100.0 * (promoters - detractors) / people).round
  end
  Answer = Data.define(:user_id, :score, :at, :id) do
    def day = NpsResponse.day(at)
  end

  DAYS = 7
  LATEST = 30

  attr_reader :now

  def initialize(now: Time.current)
    @now = now
    @answers = participants_answers.pluck(:user_id, :score, :created_at, :id).map { Answer.new(*it) }
  end

  def any? = @answers.any?

  # The 7 days ending today, today so far included.
  def last_7_days = span(today)

  # The newest answers, with their people and projects.
  def latest = newest_first.limit(LATEST)

  # Every answer, newest first (D-119). The same people as `latest`: admins are left out.
  def all = newest_first

  def count = @answers.size

  def span(last_day)
    days = (last_day - (DAYS - 1))..last_day
    newest = @answers.select { days.cover?(it.day) && it.at <= @now }.group_by(&:user_id).values.map { |answers| answers.max_by { [ it.at, it.id ] } }
    Span.new(last_day:, promoters: newest.count { NpsResponse::PROMOTERS.cover?(it.score) },
             passives: newest.count { NpsResponse::PASSIVES.cover?(it.score) }, detractors: newest.count { NpsResponse::DETRACTORS.cover?(it.score) })
  end

  private
    def today = NpsResponse.day(@now)

    def newest_first = participants_answers.includes(:user, :project).order(created_at: :desc, id: :desc)

    def participants_answers
      listed = Rails.configuration.x.admin_slack_ids.to_a
      NpsResponse.joins(:user).merge(User.where(slack_id: nil).or(User.where.not(slack_id: listed)))
    end
end
