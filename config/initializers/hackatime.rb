# Hackatime, where hours come from. Its public stats API lists the projects someone's logged time on.
Rails.application.config.x.hackatime_url = ENV.fetch("HACKATIME_URL", "https://hackatime.hackclub.com")
