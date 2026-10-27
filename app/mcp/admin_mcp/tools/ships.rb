module AdminMcp::Tools::Ships
  # The Ships page: every ship, in review first (oldest at the top), then decided.
  class FindShips < AdminMcp::Tool
    reads "find_ships", "Find ships",
          "Ships as the Ships page lists them: who, the project, what they shipped, hours, date and status (in_review is awaiting a review, awaiting_fraud " \
          "is awaiting the fraud check, then approved, changes_needed, or rejected for good). status picks in_review (default, oldest first), awaiting_fraud, " \
          "approved, changes_needed, rejected, decided (newest first) or all (waiting first). " \
          "query narrows by the ship's title or who it's by. Answers { total, ships }; get_ship opens one in full.",
          { status: { type: "string", enum: %w[in_review awaiting_fraud approved changes_needed rejected decided all], description: "Default in_review." },
            query: { type: "string", description: "Part of the ship's title, or the person's name, email or Slack display name." },
            project_id: { type: "integer", description: "Only this project's ships." },
            user_id: { type: "integer", description: "Only this person's ships." },
            **AdminMcp::Tool::PAGE }

    def self.run(args, _caller)
      ships = Ship.includes(:decided_by, project: :user)
      ships = case (status = args[:status] || "in_review")
      when "in_review" then ships.in_review.order(:created_at, :id)
      when "decided" then ships.decided.order(decided_at: :desc, id: :desc)
      when "awaiting_fraud" then ships.awaiting_fraud.order(:reviewed_at, :id)
      when "approved", "changes_needed", "rejected" then ships.where(status:).order(decided_at: :desc, id: :desc)
      else ships.order(Arel.sql("status in ('in_review', 'awaiting_fraud') desc, case when status in ('in_review', 'awaiting_fraud') then created_at end asc, decided_at desc nulls last, id desc"))
      end
      ships = ships.where(project_id: args[:project_id]) if args[:project_id]
      ships = ships.where(project_id: Project.where(user_id: args[:user_id]).select(:id)) if args[:user_id]
      if args[:query].present?
        pattern = "%#{Ship.sanitize_sql_like(args[:query].to_s.strip)}%"
        ships = ships.where("ships.title ILIKE :q OR ships.project_id IN (:projects)", q: pattern, projects: Project.search(args[:query].to_s.strip).select(:id))
      end
      total, rows = page(ships, args)
      { total:, ships: rows.map { AdminMcp::Present.ship(it) } }
    end
  end

  # Everything the ship review page shows.
  class GetShip < AdminMcp::Tool
    reads "get_ship", "Get one ship",
          "A ship in full, as the review page shows it: who shipped it, what they submitted (title, description, what they changed, repository, playable link), " \
          "the hours Hackatime counted and the handbook's limits on them (AI coding and art time, the most to approve, the reason for a cut), the repository's commits since Save Point began, " \
          "the evidence the page shows beside it (seconds per linked Hackatime project at ship time and now, the repository's facts and latest release with a flag when it predates Save Point, the Lapse sessions and art share, the participant's identity and Hackatime trust level, accounts with the same repo or Slack account, the Stardance check, and the Telescreen and Lapse review links), " \
          "the earlier ship in the Unified YSWS DB (with a warning when its record was approved after Save Point began), the project's other ships, and the verdict. " \
          "The verdict holds review_feedback (the note the participant sees), review_judgement (the reviewer's internal note) and review_checklist (the ticks, frozen at the decision), " \
          "the review's coding and art hours, the fraud check (fraud_status, deduction, notes), who held each, and the send_backs (a ship that waited for its fraud check and went back to review). " \
          "For a ship in review, checklist_defaults lists the ticks the app would pre-fill, each with its reason. " \
          "For a ship in review it asks Hackatime for the AI coding and art time once, as opening the page does. It looks up GitHub and Airtable, so it can take a few seconds.",
          { ship_id: { type: "integer", description: "The ship ID." } }, required: %w[ship_id]

    def self.run(args, _caller)
      ship = Ship.includes(:decided_by, project: :user).find(args[:ship_id])
      ship.fetch_hackatime_categories!
      review = ship.review
      project = ship.project
      earlier = review.earlier_ship
      overlap = earlier.entries.find { (date = AirtableFields.parse_date(it.approved_at)) && date > project.hours_start.utc.to_date }
      AdminMcp::Present.ship(ship).merge(
        user: AdminMcp::Present.person(project.user), description: ship.description, changes_made: ship.changes_made.presence,
        repo_url: ship.repo_url, demo_url: ship.demo_url, has_screenshot: ship.screenshot.attached?,
        hours_start: project.hours_start, hours_start_source: project.hours_start_source, hours_counted: ship.counted_hours.to_f, hours_when_shipped: ship.hours.to_f, hours_now: project.hours_logged.to_f,
        approved_hours: ship.approved_hours&.to_f, claimed_hours: ship.claimed_hours&.to_f,
        technical_features: ship.technical_features, deflation_reason: ship.deflation_reason,
        limits: AdminMcp::Present.limits(review.limits),
        evidence: AdminMcp::Present.evidence(Ship::Evidence.new(ship, commits: review.commits), review.limits),
        commits: { status: review.commits.status, message: review.commits.message, more: review.commits.more,
                   list: review.commits.commits.map { { sha: it.sha, message: it.message, author: it.author, date: it.date, url: it.url } } },
        earlier_ship: { status: earlier.status, message: earlier.message, entries: earlier.entries.map(&:to_h),
                        overlap_program: overlap&.program },
        review_feedback: ship.review_feedback, review_judgement: ship.review_judgement, review_checklist: ship.review_checklist,
        review: { reviewer: ship.reviewer&.first_name, reviewed_at: ship.reviewed_at, coding_hours: ship.review_coding_hours&.to_f,
                  art_hours: ship.review_art_hours&.to_f, hours: ship.review_hours&.to_f },
        fraud: { status: ship.fraud_status, reviewer: ship.fraud_reviewer&.first_name, reviewed_at: ship.fraud_reviewed_at,
                 deduction_hours: ship.fraud_deduction_hours.to_f, notes: ship.fraud_notes },
        send_backs: ship.send_backs.includes(:user).map { { by: it.user.first_name, reason: it.reason, at: it.created_at, earlier_review: it.earlier_review } },
        held_by: Claim.live.where(ship:).includes(:user).map { { stage: it.stage, user: it.user.first_name } },
        checklist_defaults: (ship.checklist_defaults(earlier:, limits: review.limits).transform_values { |(ticked, reason)| { ticked:, reason: } } if ship.in_review?),
        justifications: (AirtableFields.justifications(ship, earlier:) if ship.approved? && earlier.checked?),
        other_ships: review.others.map { { id: it.id, status: it.status, hours: it.hours.to_f, shipped_at: it.created_at } }
      )
    end
  end

  # What the review and fraud tools check before they change a ship: not your own (D-063), and not one another admin has open.
  module Guard
    def self.check!(ship, stage, caller)
      raise AdminMcp::Refused, "Someone else judges your own ship." if ship.by?(caller.user)
      raise AdminMcp::Refused, "Someone else holds this ship." if Claim.held_by_other?(ship, stage, caller.user)
    end
  end

  class ReviewShip < AdminMcp::Tool
    writes "review_ship", "Review a ship",
           "Gives a ship in review its verdict, once (the review page's buttons, Ship#decide!). approved holds the coding and art hours you set (each defaults to the most the limits allow and is " \
           "clamped to it: AI coding counts at a third, art at most 30% of the total; see get_ship's limits) and needs technical_features, and a deflation_reason when you go below what the rules allow. " \
           "It then moves to the fraud check (fraud_ship): the hours are not the participant's to spend until that passes. changes_needed sends it back and needs feedback: the note the participant sees (D-049). " \
           "rejected is final and needs judgement. banned is fraud found at review: it needs evidence, rejects the ship and bans the account. " \
           "Nobody is told by this: the participant sees the result on the site. You can't review your own ship, or one another admin has open. " \
           "Answers { decided, errors, message, ship }: when a field is missing, nothing is decided and errors says which. Read get_ship first.",
           { ship_id: { type: "integer", description: "The ship ID." },
             decision: { type: "string", enum: Ship::DECISIONS, description: "approved (to the fraud check), changes_needed, rejected (final), or banned (fraud: reject and ban)." },
             coding_hours: { type: "number", minimum: 0, description: "For approved: the coding hours to approve. Defaults to the most the limits allow. On a later ship of a project (one with an earlier approval) these are the NEW coding hours since that approval (D-097)." },
             art_hours: { type: "number", minimum: 0, description: "For approved: the art hours to approve. Defaults to the most the art hold allows. On a later ship these are the NEW art hours since the earlier approval." },
             technical_features: { type: "string", description: "For approved: the specific technical features that explain the hours." },
             deflation_reason: { type: "string", description: "For approved: why you approve less than the rules allow." },
             feedback: { type: "string", description: "The note to the participant. Required for changes_needed, optional otherwise." },
             judgement: { type: "string", description: "Your internal judgement. Required for rejected. It goes into the Airtable justification." },
             evidence: { type: "string", description: "For banned: what shows the fraud." } },
           required: %w[ship_id decision]

    def self.run(args, caller)
      ship = Ship.includes(:decided_by, project: :user).find(args[:ship_id])
      Guard.check!(ship, "review", caller)
      # Asked once, as opening the review page does, so the limits are known.
      ship.fetch_hackatime_categories!
      decided = ship.decide!(args[:decision], by: caller.user, coding_hours: args[:coding_hours]&.to_s, art_hours: args[:art_hours]&.to_s,
                             technical_features: args[:technical_features], deflation_reason: args[:deflation_reason],
                             feedback: args[:feedback], judgement: args[:judgement], evidence: args[:evidence],
                             checklist_defaults: ship.checklist_defaults(earlier: Ship::EarlierShip.for(ship)))
      ship.claims.where(stage: "review").delete_all if decided
      message = if decided then nil
      elsif ship.errors.none? then "That one's been decided already."
      else "Not decided: #{ship.errors.full_messages.to_sentence}."
      end
      { decided:, message:, errors: ship.errors.to_hash, ship: AdminMcp::Present.ship(ship.reload) }
    end
  end

  class FraudShip < AdminMcp::Tool
    writes "fraud_ship", "Fraud-check a ship",
           "The fraud stage of a ship that review approved (the fraud page's buttons). pass makes it approved: the hours are the participant's to spend and it goes to Airtable. " \
           "deduct passes it with deduct_hours taken off the review's hours, and needs notes. ban rejects the ship for good and bans the account (its other ships still waiting are rejected), and needs notes: " \
           "what shows the fraud. send_back returns it to review, with a reason. Nobody is told by this. You can't check your own ship, or one another admin has open. " \
           "Answers { decided, errors, message, ship }. Read get_ship first.",
           { ship_id: { type: "integer", description: "The ship ID." },
             verdict: { type: "string", enum: Ship::FRAUD_VERDICTS + %w[send_back], description: "pass, deduct, ban, or send_back." },
             deduct_hours: { type: "number", minimum: 0, description: "For deduct: the hours to take off." },
             notes: { type: "string", description: "Required for deduct and ban." },
             reason: { type: "string", description: "Required for send_back." } },
           required: %w[ship_id verdict]

    def self.run(args, caller)
      ship = Ship.includes(:decided_by, project: :user).find(args[:ship_id])
      Guard.check!(ship, "fraud", caller)
      by = caller.user
      decided = case args[:verdict]
      when "pass" then ship.pass_fraud!(by:, notes: args[:notes])
      when "deduct" then ship.pass_fraud!(by:, deduction: args[:deduct_hours].to_s, notes: args[:notes])
      when "ban" then ship.awaiting_fraud? && ship.ban_for_fraud!(by:, notes: args[:notes])
      when "send_back" then ship.send_back_to_review!(by:, reason: args[:reason])
      else raise AdminMcp::Refused, "verdict is pass, deduct, ban or send_back."
      end
      ship.claims.where(stage: "fraud").delete_all if decided
      message = if decided then nil
      elsif ship.errors.none? then "That one isn't waiting for its fraud check."
      else "Not decided: #{ship.errors.full_messages.to_sentence}."
      end
      { decided:, message:, errors: ship.errors.to_hash, ship: AdminMcp::Present.ship(ship.reload) }
    end
  end
end
