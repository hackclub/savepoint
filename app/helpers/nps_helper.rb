module NpsHelper
  # Which of NPS's groups a score puts a person in.
  def nps_group(score)
    if NpsResponse::PROMOTERS.cover?(score) then "promoter"
    elsif NpsResponse::PASSIVES.cover?(score) then "passive"
    else "detractor"
    end
  end

  # An NPS as people write it: +40, 0, -25, or a dash for no answers.
  def nps_value(nps) = nps.nil? ? "—" : nps.zero? ? "0" : format("%+d", nps)
end
