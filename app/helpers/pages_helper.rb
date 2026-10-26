module PagesHelper
  def hours_per_reward
    Program::HOURS_PER_REWARD
  end

  def program_dates
    Program::DATES
  end

  def hackatime_url
    "https://hackatime.hackclub.com/"
  end

  def footer_links
    {
      "slack" => "https://hackclub.com/slack/",
      "clubs" => "https://hackclub.com/clubs/",
      "privacy" => "https://hackclub.com/privacy-and-terms",
      "fulfillment" => "https://forms.hackclub.com/bounty"
    }
  end
end
