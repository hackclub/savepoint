# Links into Telescreen, Hack Club's review workbench (D-105, D-114). The one place that builds them, so the review page
# (Ship::Evidence) and the admin projects list (Admin::ProjectsController's view) open the same URL. Nothing here asks
# Hackatime: it reads only the numeric id stored on the user (users.hackatime_uid).
module Telescreen
  HOST = "https://telescreen.hackclub.com"
  LAPSE_REVIEW = "#{HOST}/workbench/lapse"
  HACKATIME_WORKBENCH = "#{HOST}/workbench/hackatime/overview"

  # The numeric Hackatime id of a user, or nil when none is stored or it isn't all digits.
  def self.hackatime_id(user) = user.hackatime_uid.to_s[/\A\d+\z/]

  # The participant's Hackatime workbench for these linked projects, or nil without a numeric id (nothing to open for them).
  def self.hackatime_url(user, names)
    id = hackatime_id(user) or return

    query = "u=#{id}"
    names = Array(names)
    query += "&p=#{names.map { CGI.escape(it) }.join(",")}" if names.any?
    "#{HACKATIME_WORKBENCH}?#{query}"
  end

  # The same, or the bare workbench when there is no numeric id.
  def self.hackatime_url_or_workbench(user, names) = hackatime_url(user, names) || HACKATIME_WORKBENCH

  def self.lapse_review_url(user)
    id = hackatime_id(user)
    id ? "#{LAPSE_REVIEW}?u=#{id}" : LAPSE_REVIEW
  end
end
