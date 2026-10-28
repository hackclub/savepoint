# The admin ships pages (Admin::ShipsController).
module Admin::ShipsHelper
  SHIP_STATUS_LABELS = { "in_review" => "In review", "awaiting_fraud" => "Fraud check", "approved" => "Approved",
                         "changes_needed" => "Changes needed", "rejected" => "Rejected", "superseded" => "Replaced" }.freeze

  # "In review" (waiting for a review), "Fraud check" (waiting for it), "Approved", "Changes needed", "Rejected" or "Replaced" (the participant shipped again before its first review).
  def ship_status_label(ship)
    SHIP_STATUS_LABELS.fetch(ship.status)
  end

  # "Approved · Orpheus · Oct 13": the decision, who made it and when; the stage until then.
  def ship_decision(ship)
    return ship_status_label(ship) if ship.pending?
    # D-109: a replaced ship has no verdict, only the date the participant shipped again.
    return "#{ship_status_label(ship)} · #{ship.updated_at.strftime("%b %-d")}" if ship.superseded?

    "#{ship_status_label(ship)} · #{ship.decided_by&.first_name.presence || "someone"} · #{ship.decided_at.strftime("%b %-d")}"
  end

  # D-063: seconds from Hackatime as "1.5 hrs", or "unknown" when it didn't say.
  def evidence_hours(seconds)
    seconds.nil? ? "unknown" : Ship::Limits.hrs(seconds.to_d / 3600)
  end

  # The badge tone for a Hackatime trust level: red is a ban (D-051).
  def trust_level_tone(level)
    { "red" => "coral", "yellow" => "gold", "green" => "mint", "blue" => "mint" }[level]
  end
end
