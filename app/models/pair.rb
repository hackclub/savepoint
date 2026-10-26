# Two projects building side by side: separate games in their own tools, one pair streak. You're paired by
# accepting someone's invite link (or, later, being matched). A project is in one pair at most.
class Pair < ApplicationRecord
  belongs_to :first_project, class_name: "Project"
  belongs_to :second_project, class_name: "Project"
  has_many :pomodoros, class_name: "BuddyPomodoro", dependent: :destroy
  has_many :rewards, dependent: :destroy

  validate :two_projects_not_paired_yet, on: :create

  def self.of(project)
    where(first_project: project).or(where(second_project: project)).first
  end

  def buddy_of(project)
    project == first_project ? second_project : first_project
  end

  def projects = [ first_project, second_project ]

  # Whether you've done a pomodoro together: it ran with both of you in it.
  def pomodoro_together? = pomodoros.where.not(joined_at: nil).exists?

  # The pomodoro you're doing together right now, if there is one.
  def live_pomodoro
    pomodoros.live.first.then { |pomodoro| pomodoro if pomodoro&.live? }
  end

  private
    def two_projects_not_paired_yet
      if first_project == second_project
        errors.add(:base, "You can't pair with yourself")
      elsif [ first_project, second_project ].any? { |project| Pair.of(project) }
        errors.add(:base, "One of you already has a buddy")
      end
    end
end
