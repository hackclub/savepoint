# The ship checker's checks that need the internet, run live while the participant fills in the form (playground's
# interactive checker, cut down to what fits Save Point): is the repository public, does it have a README, does the playable link
# link load, and has the repository seen commits since Save Point began. The checks that need only the form (title,
# description, what changed, screenshot) run in the browser (ship_controller.js).
#
# A check that could not run (GitHub's rate limit, a 5xx, a timeout) is "unchecked" (D-022): it never blocks and the participant is
# shown nothing about it. Only a definite answer fails: GitHub says 404 for the repository or its README, or the playable link's
# host answers 4xx or 5xx. Never raises.
#
# The answers are cached by what they depend on: the repository's by its URL, the playable link's by the link. A definite answer
# stays 10 minutes, a definite failure 1 minute, and an unchecked one isn't kept. One exception: while the repository's README lacks
# the playable link (or there is no README), it is read again on each ask, so a participant who fixes it and comes back passes at once.
class Ship::Checklist
  Item = Data.define(:key, :label, :state, :detail, :blocker) do
    # state: :ok, :fail, :warn (worth a look), :wait (nothing to check yet), :unchecked (couldn't ask, D-022).
    def as_json(*) = { key: key.to_s, label:, state: state.to_s, detail:, blocker: }
  end

  API = "https://api.github.com"
  LABELS = { repo: "Make the repository public", readme: "Add a README to the repository",
             readme_demo: "Put your playable link in the README", demo: "Make sure your playable link loads", commits: "Commit since Save Point began" }.freeze

  def initialize(repo_url:, demo_url:)
    @repo_url = normalize(repo_url)
    @demo_url = normalize(demo_url)
    @github = Ship::Commits.repo_path(@repo_url)
  end

  def items
    @items ||= begin
      group = repo_group
      demo = remember([ "ship-link", @demo_url ]) { demo_item }
      [ group[:repo], group[:readme], readme_demo_item(group, demo), demo, group[:commits] ]
    end
  end

  # D-019, D-020: whether the README certainly lacks the playable link: it was read, and the link isn't in it (or there is no README).
  # A README that couldn't be read never counts, so a slow GitHub never blocks a ship. Used by Ship's validation.
  def readme_without_demo?
    return false unless @github && web_url?(@demo_url)

    response = github("/repos/#{@github}/readme")
    return true if response.status == 404
    response.ok? && !readme_mentions_demo?(decode_readme(response))
  rescue Web::Error, JSON::ParserError
    false
  end

  # Does this README text contain the playable link? Anywhere in it counts (Armand: "contain the playable link, not
  # match"), ignoring the scheme (http or https, or none), the case of the host, and a trailing slash.
  def self.mentions_link?(text, url)
    uri = URI.parse(url.to_s.strip.then { it.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? it : "https://#{it}" })
    return false if uri.host.blank?

    port = ":#{uri.port}" if uri.port && uri.port != uri.default_port
    query = "\\?#{Regexp.escape(uri.query)}" if uri.query.present?
    link = "(?i:#{Regexp.escape(uri.host)})#{port}#{Regexp.escape(uri.path.to_s.chomp("/"))}#{query}"
    text.to_s.match?(/#{link}/)
  rescue URI::InvalidURIError
    false
  end

  def blocked? = items.any? { it.blocker && it.state == :fail }

  def as_json(*) = { items: items.as_json, blocked: blocked? }

  private
    # The repository's three checks and its README text, asked once for a repository (cached by its URL). The README is the exception
    # to "cached by repository": while it lacks the playable link, the participant is about to fix it, so it is read again (one call)
    # instead of served from the cache.
    def repo_group
      key = [ "ship-repo", @repo_url ]
      cached = Rails.cache.read(key)
      if cached.nil?
        repo = repo_item
        readme = readme_item(repo)
        return store(key, { repo:, readme:, commits: commits_item(repo), text: @readme_text })
      end
      return cached unless readme_may_have_changed?(cached)

      readme = readme_item(cached[:repo])
      store(key, cached.merge(readme:, text: @readme_text))
    end

    def readme_may_have_changed?(group)
      return false unless @github && group[:repo].state == :ok

      group[:readme].state == :fail || (group[:readme].state == :ok && web_url?(@demo_url) && !readme_mentions_demo?(group[:text]))
    end

    # Cached by key: definite for 10 minutes, a definite failure for 1, and what couldn't be checked not at all. The block gives an item or
    # a hash of them.
    def remember(key)
      cached = Rails.cache.read(key)
      return cached if cached

      store(key, yield)
    end

    def store(key, value)
      items = value.is_a?(Hash) ? value.values.grep(Item) : [ value ]
      states = items.map(&:state)
      ttl = if states.include?(:unchecked) then nil
      elsif states.include?(:fail) then 1.minute
      else 10.minutes
      end
      Rails.cache.write(key, value, expires_in: ttl) if ttl
      value
    end

    def item(key, state, detail = nil, blocker: false) = Item.new(key:, label: LABELS.fetch(key), state:, detail:, blocker:)

    def repo_item
      return item(:repo, :wait, "Add the repository link.", blocker: true) if @repo_url.blank?
      return item(:repo, :fail, "That isn't a link.", blocker: true) unless web_url?(@repo_url)
      return probe(:repo, @repo_url, "The repository didn't load without signing in.") unless @github

      response = github("/repos/#{@github}")
      if response.ok? then response.json["private"] ? item(:repo, :fail, "The repository is private. Make it public.", blocker: true) : item(:repo, :ok)
      elsif response.status == 404 then item(:repo, :fail, "GitHub can't find #{@github}. Check the link and that it is public.", blocker: true)
      else item(:repo, :unchecked)
      end
    rescue Web::Error, JSON::ParserError
      item(:repo, :unchecked)
    end

    def readme_item(repo)
      return item(:readme, :unchecked) if repo.state == :unchecked
      return item(:readme, :wait, blocker: true) unless repo.state == :ok
      return item(:readme, :ok, "Not on GitHub, so a reviewer looks by hand.") unless @github

      response = github("/repos/#{@github}/readme")
      if response.ok? then @readme_text = decode_readme(response); item(:readme, :ok)
      elsif response.status == 404 then item(:readme, :fail, "Add a README that says what the game is and how to run it.", blocker: true)
      else item(:readme, :unchecked)
      end
    rescue Web::Error, JSON::ParserError
      item(:readme, :unchecked)
    end

    # D-019. Waits until there is a public README and a playable link to look for. Not on GitHub, a reviewer looks by hand.
    def readme_demo_item(group, demo)
      readme = group[:readme]
      return item(:readme_demo, :unchecked) if readme.state == :unchecked
      return item(:readme_demo, :wait, blocker: true) unless readme.state == :ok && demo.state != :wait
      return item(:readme_demo, :ok, "Not on GitHub, so a reviewer looks by hand.") unless @github
      return item(:readme_demo, :wait, blocker: true) unless web_url?(@demo_url)

      if readme_mentions_demo?(group[:text]) then item(:readme_demo, :ok)
      elsif (found = same_host_link(group[:text]))
        item(:readme_demo, :fail, "Your README links #{found}, but your playable link is #{@demo_url}. Make them the same: change the README or the playable link. Then come back here.", blocker: true)
      else item(:readme_demo, :fail, "Add your playable link, #{@demo_url}, to the README, so people can find the game from the repository. Then come back here.", blocker: true)
      end
    end

    # D-123: the first http(s) link in the README on the playable link's host, so a near miss can be named.
    def same_host_link(text)
      host = URI.parse(@demo_url.to_s.strip.then { it.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? it : "https://#{it}" }).host.to_s.downcase
      return if host.blank?

      text.to_s.scan(%r{https?://[^\s<>"'\])]+}i).each do |link|
        link = link.sub(/[.,;:!?*_`]+\z/, "")
        return link if URI.parse(link).host.to_s.downcase == host
      rescue URI::InvalidURIError
        next
      end
      nil
    rescue URI::InvalidURIError
      nil
    end

    def readme_mentions_demo?(text) = self.class.mentions_link?(text, @demo_url)

    def decode_readme(response)
      body = response.json
      body["encoding"] == "base64" ? Base64.decode64(body["content"].to_s).force_encoding("UTF-8").scrub : body["content"].to_s
    end

    def demo_item
      return item(:demo, :wait, "Add the playable link.", blocker: true) if @demo_url.blank?
      return item(:demo, :fail, "That isn't a link.", blocker: true) unless web_url?(@demo_url)

      probe(:demo, @demo_url, "The link didn't load for someone who isn't signed in.")
    end

    def commits_item(repo)
      return item(:commits, :unchecked) if repo.state == :unchecked
      return item(:commits, :wait) unless repo.state == :ok && @github

      result = Ship::Commits.new(@repo_url, since: Program::STARTS_AT, until_time: Time.current).fetch
      if !result.ok? then item(:commits, result.status == :not_found ? :warn : :unchecked, (result.message if result.status == :not_found))
      elsif result.commits.empty? then item(:commits, :warn, "No commits since Save Point began. The reviewer will notice.")
      else item(:commits, :ok, "#{result.commits.size}#{"+" if result.more} commit#{"s" unless result.commits.size == 1} since the start.")
      end
    end

    # Any 2xx or 3xx is a page that loads. A 403 or 405 to HEAD gets a second try with GET.
    def probe(key, url, failure)
      response = Web.head(url, public_only: true)
      response = Web.get(url, public_only: true, read_body: false) if response.status.in?([ 403, 405, 501 ])
      response.status < 400 ? item(key, :ok) : item(key, :fail, failure, blocker: true)
    rescue Web::Timeout
      item(key, :unchecked)
    rescue Web::Error => e
      item(key, :fail, "#{failure} (#{e.message.first(60)})", blocker: true)
    end

    def github(path) = Web.get("#{API}#{path}", headers: Ship::Commits.headers)

    def normalize(url)
      value = url.to_s.strip
      value.present? && !value.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? "https://#{value}" : value
    end

    def web_url?(url) = url.match?(Ship::URL)
end
