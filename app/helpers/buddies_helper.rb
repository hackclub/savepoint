module BuddiesHelper
  # One person's minutes today (their viewer's own calendar date, as on the leaderboard) against their daily pace.
  def today_minutes(project)
    { minutes: (project.hours_today(today: Leaderboard.date_for(current_user)) * 60).round, pace: project.pace_minutes.to_i }
  end

  # Their Slack display name, never their real name (see User#public_name).
  def buddy_name(project)
    project.user.public_name
  end

  # What the two of you have logged since the program started, counted hours from the same place the rest of the app
  # reads them (User#hours_in): the sum, then yours and theirs.
  def pair_hours(project)
    mine = project.user.hours_in(Program::DATES)
    theirs = project.buddy.user.hours_in(Program::DATES)
    { together: (mine + theirs).round(1), mine:, theirs: }
  end

  # "savepoint.hackclub.com/b/k3j9x2qa", for showing; the link itself is buddy_invite_url.
  def buddy_invite_link(project)
    buddy_invite_url(project.buddy_code!).delete_prefix("https://").delete_prefix("http://")
  end
end
