# D-087, D-090: accounts whose projects share a repo are flagged for the admin to judge, but each still counts in the DAU
# (most are jam teams). Two projects share a repo when their repo links are the same after Ship::EarlierShip.normalize (so a title and a repo shared is covered too: the
# repo alone is enough). The admin flags each pair, so a person can judge one builder or a team.
class SharedGames
  Pair = Data.define(:project, :other)

  # Each pair of projects, by different accounts, that share a repo, in a stable order.
  def self.pairs(user_ids: nil)
    groups(user_ids).values.flat_map { |projects| projects.sort_by(&:id).combination(2).map { |project, other| Pair.new(project, other) } }.sort_by { |pair| [ pair.project.id, pair.other.id ] }
  end

  # The projects that share a repo with this one, for the flag beside it.
  def self.sharing_with(project, user_ids: nil)
    key = key_for(project.repo_url) or return []
    groups(user_ids)[key].to_a.reject { |other| other.user_id == project.user_id }
  end

  def self.groups(user_ids)
    scope = Project.where.not(repo_url: [ nil, "" ]).includes(:user)
    scope = scope.where(user_id: user_ids) if user_ids
    scope.group_by { |project| key_for(project.repo_url) }.select { |key, projects| key && projects.map(&:user_id).uniq.size > 1 }
  end
  private_class_method :groups

  # A repo link that names something: "github.com/owner/repo", not "github.com".
  def self.key_for(url)
    key = Ship::EarlierShip.normalize(url)
    key if key.count("/") >= 2 || (key.count("/") == 1 && key.length >= 8)
  end
  private_class_method :key_for
end
