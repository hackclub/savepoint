module AdminMcp::Tools::Ships
  # The Ships page: every ship, in review first (oldest at the top), then decided.
  class FindShips < AdminMcp::Tool
    reads "find_ships", "Find ships",
          "Ships as the Ships page lists them: who, the project, what they shipped, hours, date and status (in_review is awaiting a review, awaiting_fraud " \
          "is awaiting the fraud check, then approved, changes_needed, or rejected for good; superseded is a ship the participant replaced by shipping again before its first review). status picks in_review (default, oldest first), awaiting_fraud, " \
          "approved, changes_needed, rejected, superseded, decided (newest first) or all (waiting first). " \
          "query narrows by the ship's title or who it's by. Answers { total, ships }; get_ship opens one in full.",
          { status: { type: "string", enum: %w[in_review awaiting_fraud approved changes_needed rejected superseded decided all], description: "Default in_review." },
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
      when "superseded" then ships.superseded.order(id: :desc)
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
          "the evidence the page shows beside it (seconds per linked Hackatime project at ship time and now, the repository's facts and latest release with a flag when it predates Save Point, the Lapse sessions and art share, the participant's identity and Hackatime trust level, accounts with the same repo or Slack account, and the Telescreen and Lapse review links), " \
          "the earlier ship in the Unified YSWS DB (with a warning when its record was approved after Save Point began), the project's other ships, and the verdict. " \
          "The verdict holds review_feedback (the note the participant sees), review_judgement (the reviewer's internal note) and review_checklist (the ticks, frozen at the decision), " \
          "the review's coding and art hours, the fraud check (fraud_status, deduction, notes), who held each, and the send_backs (a ship that waited for its fraud check and went back to review). " \
          "For a ship in review, checklist_defaults lists the ticks the app would pre-fill, each with its reason. " \
          "For an approved ship, justifications holds what goes to Airtable, and deflation_problem says which part of a deflation has no reason (D-111: every deflation needs one), so the sync holds it back. " \
          "For a ship in review it asks Hackatime for the AI coding and art time once, as opening the page does. It looks up GitHub and Airtable, so it can take a few seconds.",
          { ship_id: { type: "integer", description: "The ship ID." } }, required: %w[ship_id]

    def self.run(args, _caller)
      ship = Ship.includes(:decided_by, project: :user).find(args[:ship_id])
      ship.fetch_hackatime_categories!
      review = ship.review
      project = ship.project
      earlier = review.earlier_ship
      overlap = earlier.overlapping_entry(user: project.user, from: project.hours_start.utc.to_date, to: ship.created_at.utc.to_date)
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
        review_draft: ship.review_draft, review_draft_updated_at: ship.review_draft_updated_at, review_draft_updated_by: ship.review_draft_updated_by&.first_name,
        review: { reviewer: ship.reviewer&.first_name, reviewed_at: ship.reviewed_at, coding_hours: ship.review_coding_hours&.to_f,
                  art_hours: ship.review_art_hours&.to_f, hours: ship.review_hours&.to_f },
        fraud: { status: ship.fraud_status, reviewer: ship.fraud_reviewer&.first_name, reviewed_at: ship.fraud_reviewed_at,
                 deduction_hours: ship.fraud_deduction_hours.to_f, notes: ship.fraud_notes },
        send_backs: ship.send_backs.includes(:user).map { { by: it.user.first_name, reason: it.reason, at: it.created_at, earlier_review: it.earlier_review } },
        held_by: Claim.live.where(ship:).includes(:user).map { { stage: it.stage, user: it.user.first_name } },
        real_name: AdminMcp::Tools::Ships.real_name(ship),
        checklist_defaults: (ship.checklist_defaults(earlier:, limits: review.limits).transform_values { |(ticked, reason)| { ticked:, reason: } } if ship.in_review?),
        justifications: (AirtableFields.justifications(ship, earlier:, strict: false) if ship.approved? && earlier.checked?),
        deflation_problem: (AirtableFields.deflation_problem(ship) if ship.approved?),
        other_ships: review.others.map { { id: it.id, status: it.status, hours: it.hours.to_f, shipped_at: it.created_at } }
      )
    end
  end

  # What the Real name item (D-143) asks about: the first and last name exactly as the Unified YSWS row carries them, with the app's own doubt if any.
  def self.real_name(ship)
    check = Ship::RealName.new(ship)
    first, last = check.names
    { first_name: first, last_name: last, concern: check.concern, ticked: ship.real_name_checked?, ticked_for: [ ship.real_name_first, ship.real_name_last ].compact,
      ticked_by: ship.real_name_ticked_by&.first_name, ticked_at: ship.real_name_ticked_at, tick_is_stale: ship.real_name_stale?,
      unified_holds: (ship.approved? ? ship.unified_holds : []), changed_after_unified_at: ship.changed_after_unified_at,
      ysws_eligible: ship.project.user.ysws_eligible? }
  end

  # What the review and fraud tools check before they change a ship: not your own (D-063), and not one another admin has open.
  module Guard
    def self.check!(ship, stage, caller)
      raise AdminMcp::Refused, "Someone else judges your own ship." if ship.by?(caller.user)
      raise AdminMcp::Refused, "Someone else holds this ship." if Claim.held_by_other?(ship, stage, caller.user)
    end
  end

  # D-139: the verdict DM for a ship decided before the bot sent them (Nudge::ChangesNeeded, Nudge::Rejected), once.
  class SendVerdictDm < AdminMcp::Tool
    writes "send_verdict_dm", "Send a ship's verdict DM",
           "Sends the participant the bot's Slack DM for a ship's verdict, once: for a changes_needed ship the changes-needed DM with the reviewer's note and the deadline to ship again, in their time zone " \
           "(D-139), for a rejected ship the rejection DM (D-137). For ships decided before those DMs existed; newer verdicts send theirs on their own. The usual rules hold: quiet hours and the gap after another DM " \
           "queue it for later rather than drop it. Refuses other statuses, an admin's own ship, a banned or stopped participant, and a ship whose DM was sent already. " \
           "include_note: false leaves the reviewer's note out. restart_window: true (changes_needed only, and only on the project's latest decided ship) first sets the ship's reviewed_at to now, so the deadline becomes 24 hours from the send (D-140); " \
           "it is refused when the DM was sent already, and is logged under the project too. Answers { sent, queued_for, text, deadline, sent_at, kind }: text is the exact message, deadline is the local deadline (changes_needed only), and queued_for is the time it will go when it is waiting.",
           { ship_id: { type: "integer", description: "The ship ID." },
             include_note: { type: "boolean", description: "Default true. False leaves out the reviewer's note and its lead-in, so the DM carries the deadline only." },
             restart_window: { type: "boolean", description: "Default false. True restarts the Changes needed window: reviewed_at becomes now, so the deadline is 24 hours from the send. Only for the project's latest decided ship." } },
           required: %w[ship_id]

    def self.run(args, caller)
      ship = Ship.includes(project: :user).find(args[:ship_id])
      user = ship.project.user
      include_note = args[:include_note] != false
      mod = case ship.status
      when "changes_needed" then Nudge::ChangesNeeded
      when "rejected" then Nudge::Rejected
      else raise AdminMcp::Refused, "Only a changes_needed or rejected ship has a verdict DM (this one is #{ship.status})."
      end
      raise AdminMcp::Refused, "That is an admin's own ship." if user.listed_admin?
      raise AdminMcp::Refused, "That account is banned, and gets no DMs." if user.banned?
      raise AdminMcp::Refused, "The #{mod::KIND} DM for this ship was sent already." if user.nudges.delivered.where(kind: mod::KIND, ship_id: ship.id).exists?

      if args[:restart_window] == true
        raise AdminMcp::Refused, "restart_window only applies to a changes_needed ship (this one is #{ship.status})." unless ship.status == "changes_needed"
        decided = ship.project.ships.select { it.reviewed_at && %w[changes_needed awaiting_fraud approved rejected].include?(it.status) }
        raise AdminMcp::Refused, "restart_window only applies to the project's latest decided ship." unless decided.max_by(&:reviewed_at)&.id == ship.id

        AdminAuditEvent.create!(user: caller.user, admin_token: caller.token, tool: "send_verdict_dm", ids: { "ship_id" => ship.id, "project_id" => ship.project_id })
        ship.update_columns(reviewed_at: Time.current)
      end

      result = mod.send_for(ship.id, include_note:)
      if result.respond_to?(:acts_like_time?) && result.acts_like_time?
        NudgeJobFor.call(mod, ship.id, result, include_note)
        return { sent: false, queued_for: result.iso8601, kind: mod::KIND, text: nil, deadline: deadline_for(mod, ship), sent_at: nil }
      end
      raise AdminMcp::Refused, "Not sent: the participant can't be DMed (they stopped the bot, or aren't on Slack)." if result.nil?

      { sent: result.delivered, queued_for: nil, kind: mod::KIND, text: result.text, deadline: deadline_for(mod, ship), sent_at: result.sent_at&.iso8601 }
    end

    def self.deadline_for(mod, ship) = (mod.vars(ship)[:deadline] if mod.respond_to?(:vars))

    # The job that sends it once the wait is over, as the ship's own verdict would have queued.
    module NudgeJobFor
      def self.call(mod, ship_id, at, include_note)
        job = mod == Nudge::ChangesNeeded ? NudgeChangesNeededJob : NudgeRejectedJob
        job.set(wait_until: at).perform_later(ship_id, include_note)
      end
    end
  end

  # D-135: the review page's draft, written without a verdict.
  class SaveReviewDraft < AdminMcp::Tool
    writes "save_review_draft", "Save a review draft",
           "Writes fields into a ship's review draft without deciding it: the same draft the review page autosaves, so the reviewer opens the ship, sees these filled in, and picks the verdict. " \
           "Send any subset of the fields. They merge into what the draft already holds (a field you leave out is kept, an empty string clears one), and nothing is validated against the limits until a verdict is pressed. " \
           "It never decides the ship, never changes the Lapse split or AI coding the limits read (a drafted figure only fills its box), and tells nobody. The ship must be in review. " \
           "You can't draft on your own ship, or one another admin has open. Answers { saved, message, draft, ship }: draft is the whole merged draft.",
           { ship_id: { type: "integer", description: "The ship ID." },
             decision: { type: "string", enum: Ship::DECISIONS + [ "" ], description: "The verdict to have picked when the page opens. Only picks it: nothing is decided." },
             coding_hours: { type: "number", minimum: 0, description: "The coding hours to approve (on a later ship, the new ones since the earlier approval)." },
             art_hours: { type: "number", minimum: 0, description: "The art hours to approve (on a later ship, the new ones)." },
             lapse_coding_hours: { type: "number", minimum: 0, description: "The Lapse hours that were coding. Fills the Lapse box only: the limits read it once the reviewer presses Set Lapse coding on the page." },
             ai_coding_hours: { type: "number", minimum: 0, description: "The AI coding hours, above Hackatime's figure. Fills the AI box only: the limits read it once the reviewer presses Set AI coding on the page." },
             ai_reason: { type: "string", description: "With ai_coding_hours: what looked AI-generated." },
             technical_features: { type: "string", description: "The specific technical features that explain the hours." },
             deflation_reason: { type: "string", description: "Why the hours are below what the rules allow (D-111: due before an approval below the most)." },
             feedback: { type: "string", description: "The note to the participant." },
             judgement: { type: "string", description: "Your internal judgement." },
             evidence: { type: "string", description: "For a ban: what shows the fraud." } },
           required: %w[ship_id]

    def self.run(args, caller)
      ship = Ship.includes(:review_draft_updated_by, project: :user).find(args[:ship_id])
      Guard.check!(ship, "review", caller)
      merged = ship.save_review_draft!(args.slice(*Ship::REVIEW_DRAFT_KEYS.map(&:to_sym)), by: caller.user)
      return { saved: false, message: "Not saved: only a ship in review takes a draft.", draft: ship.review_draft, ship: AdminMcp::Present.ship(ship) } unless merged

      { saved: true, message: nil, draft: merged, ship: AdminMcp::Present.ship(ship.reload) }
    end
  end

  # D-136: the review page's other saves, each one the same model path the page's button takes, with no verdict and no notification.
  # They need a ship in review that is not the admin's own and not open by another admin, like save_review_draft.
  module ReviewAction
    CHECKLIST_KEYS = Ship::CHECKLIST_KEYS

    def self.answer(saved, message, ship) = { saved:, message:, ship: AdminMcp::Present.ship(ship.reload) }

    # `key` is the checklist item being saved: Real name also takes an approved ship (D-143).
    def self.open_ship(args, caller, key: nil)
      ship = Ship.includes(:decided_by, project: :user).find(args[:ship_id])
      Guard.check!(ship, "review", caller)
      raise AdminMcp::Refused, "Only a ship in review takes this." unless ship.in_review? || (key && ship.checklist_open_for?(key))

      # Asked once, as opening the review page does, so the limits are known.
      ship.fetch_hackatime_categories!
      ship
    end

    def self.problem(ship, *attributes)
      attributes.filter_map { ship.errors.messages_for(it).first }.first || ship.errors.full_messages.to_sentence
    end
  end

  # D-136: the Set Lapse coding button (Ship#set_lapse_coding!). The limits read it at once.
  class SetLapseCoding < AdminMcp::Tool
    writes "set_lapse_coding", "Set the Lapse coding split",
           "The review page's Set Lapse coding button: how many of the ship's Lapse hours were coding (Ship#set_lapse_coding!). The limits in get_ship read it at once, so the art cap and coding maximum move. " \
           "Between 0 and the Lapse hours Hackatime counted. Also fills the draft's Lapse box with the saved figure. Decides nothing and tells nobody. The ship must be in review. " \
           "You can't set it on your own ship, or one another admin has open. Answers { saved, message, ship }.",
           { ship_id: { type: "integer", description: "The ship ID." },
             lapse_coding_hours: { type: "number", minimum: 0, description: "The Lapse hours that were coding." } },
           required: %w[ship_id lapse_coding_hours]

    def self.run(args, caller)
      ship = ReviewAction.open_ship(args, caller)
      return ReviewAction.answer(false, "Not set: #{ReviewAction.problem(ship, :lapse_coding_hours)}.", ship) unless ship.set_lapse_coding!(args[:lapse_coding_hours].to_s)

      ship.save_review_draft!({ lapse_coding_hours: ship.lapse_coding_hours.to_s("F") }, by: caller.user)
      ReviewAction.answer(true, nil, ship)
    end
  end

  # D-136: the Set AI coding button (Ship#set_reviewer_ai!). The limits read it at once.
  class SetReviewerAi < AdminMcp::Tool
    writes "set_reviewer_ai", "Set the reviewer's AI coding hours",
           "The review page's Set AI coding button: the AI coding hours you set above Hackatime's figure, with why (Ship#set_reviewer_ai!). The limits in get_ship read it at once, so the coding maximum moves. " \
           "Above Hackatime's figure (or the earlier approval's) and never above the coding claimed, and a reason is required when it is above. A figure at or below Hackatime's, or none, clears it. " \
           "Also fills the draft's AI boxes with what is saved. Decides nothing and tells nobody. The ship must be in review. You can't set it on your own ship, or one another admin has open. Answers { saved, message, ship }.",
           { ship_id: { type: "integer", description: "The ship ID." },
             ai_coding_hours: { type: "number", minimum: 0, description: "The AI coding hours. Leave out to go back to Hackatime's figure." },
             ai_reason: { type: "string", description: "What looked AI-generated. Required when the hours are above Hackatime's." } },
           required: %w[ship_id]

    def self.run(args, caller)
      ship = ReviewAction.open_ship(args, caller)
      unless ship.set_reviewer_ai!(args[:ai_coding_hours].to_s, args[:ai_reason])
        return ReviewAction.answer(false, "Not set: #{ReviewAction.problem(ship, :reviewer_ai_coding_hours, :reviewer_ai_reason)}.", ship)
      end

      ship.save_review_draft!({ ai_coding_hours: ship.reviewer_ai_coding_hours&.to_s("F").to_s, ai_reason: ship.reviewer_ai_reason.to_s }, by: caller.user)
      ReviewAction.answer(true, nil, ship)
    end
  end

  # D-136: a tick of the checklist (Admin::ShipsController#checklist).
  class SetChecklistItem < AdminMcp::Tool
    writes "set_checklist_item", "Tick or untick a review checklist item",
           "A tick of the review page's checklist (it saves on every tick there). It never blocks a verdict, but real_name gates the Unified YSWS submit (D-143): the Airtable sync ticks the box only on a ship whose real_name is true. The app never ticks it itself: read first_name and last_name (get_ship's real_name) and tick it only when they are a real person's name. real_name also works on an approved ship that has not reached the Unified YSWS DB, to let it through. It refuses to tick while the first or last name is missing or an initial (D-152), and an approval needs it ticked. Your tick replaces the app's own default for that item (get_ship's checklist_defaults). " \
           "Decides nothing and tells nobody. The ship must be in review (real_name: or approved). You can't tick on your own ship, or one another admin has open. Answers { saved, message, ship }.",
           { ship_id: { type: "integer", description: "The ship ID." },
             key: { type: "string", enum: ReviewAction::CHECKLIST_KEYS, description: "runs, readme, screenshot, hours_fit, art_cap, not_double or real_name (the first and last name as get_ship shows them are a real person's name, not a handle, mash or one word)." },
             checked: { type: "boolean", description: "True to tick, false to untick." } },
           required: %w[ship_id key checked]

    def self.run(args, caller)
      raise AdminMcp::Refused, "key is one of #{ReviewAction::CHECKLIST_KEYS.join(", ")}." unless ReviewAction::CHECKLIST_KEYS.include?(args[:key].to_s)

      ship = ReviewAction.open_ship(args, caller, key: args[:key])
      return ReviewAction.answer(true, nil, ship) if ship.tick_checklist!(args[:key], args[:checked] == true, by: caller.user)

      ReviewAction.answer(false, ship.errors.full_messages.to_sentence, ship)
    end
  end

  # D-136: the Hours start panel (Admin::ShipsController#hours_start, D-065).
  class SetHoursStart < AdminMcp::Tool
    writes "set_hours_start", "Set when the project's hours start counting",
           "The review page's Hours start panel: moves the moment the project's Hackatime time starts counting, or clears the reviewer's override (the later of Save Point's start and the sign-up counts again). Saving rebuilds the participant's days. " \
           "hours_start is a UTC time, like 2026-10-12T14:30. Not before Save Point began, not in the future. Send clear: true instead to remove the override. Decides nothing and tells nobody. The ship must be in review. " \
           "You can't move the start of your own ship, or one another admin has open. Answers { saved, message, ship }.",
           { ship_id: { type: "integer", description: "The ship ID." },
             hours_start: { type: "string", description: "The new start, a UTC date and time." },
             clear: { type: "boolean", description: "True to clear the override." } },
           required: %w[ship_id]

    def self.run(args, caller)
      ship = ReviewAction.open_ship(args, caller)
      project = ship.project
      value = args[:clear] == true ? nil : parse_start(args[:hours_start])
      raise AdminMcp::Refused, "Send hours_start as a UTC date and time, or clear: true." if value == :invalid
      return ReviewAction.answer(true, "Nothing changed.", ship) if project.hours_start_override == value

      # The page logs this under the project too, so the log shows which project moved.
      AdminAuditEvent.create!(user: caller.user, admin_token: caller.token, tool: "set_hours_start", ids: { "ship_id" => ship.id, "project_id" => project.id })
      return ReviewAction.answer(false, "Not set: #{project.errors.full_messages_for(:hours_start_override).first}.", ship) unless project.update(hours_start_override: value)

      ReviewAction.answer(true, nil, ship)
    end

    # nil for none, :invalid for what isn't a time.
    def self.parse_start(text)
      return :invalid if text.blank?

      Time.find_zone!("UTC").parse(text.to_s) || :invalid
    rescue ArgumentError
      :invalid
    end
  end

  # D-136: the Edit the snapshot panel's fields (Admin::ShipsController#snapshot, Ship::Snapshot#update). The screenshots are not here.
  class EditSnapshot < AdminMcp::Tool
    writes "edit_snapshot", "Edit a ship's snapshot",
           "The review page's Edit the snapshot panel: the title, description, what they changed and the two links of this ship (Ship::Snapshot#update, so the same checks). Send any subset: a field you leave out is kept. " \
           "Only this ship changes, it is marked edited by you and sent to Airtable again. Screenshots can't be edited here. Decides nothing and tells nobody. The ship must be in review. " \
           "You can't edit your own ship, or one another admin has open. Answers { saved, message, errors, ship }: saved is false when a changed field is invalid, and errors says which.",
           { ship_id: { type: "integer", description: "The ship ID." },
             title: { type: "string" }, description: { type: "string" }, changes_made: { type: "string", description: "What they changed." },
             repo_url: { type: "string" }, demo_url: { type: "string", description: "The playable link." } },
           required: %w[ship_id]

    def self.run(args, caller)
      ship = ReviewAction.open_ship(args, caller)
      snapshot = Ship::Snapshot.new(ship)
      result = snapshot.update(args.slice(*Ship::Snapshot::FIELDS.map(&:to_sym)), by: caller.user)
      message = case result
      when true then nil
      when nil then "Nothing changed."
      else "Not saved: #{snapshot.errors.full_messages.to_sentence}."
      end
      ReviewAction.answer(result != false, message, ship).merge(errors: snapshot.errors.to_hash)
    end
  end

  # D-150: the justification text of an approved ship, fixed before the Unified YSWS DB takes it (Ship#fix_review_text!).
  class EditReviewText < AdminMcp::Tool
    # Fields of the other tools, named so a mix-up is refused rather than ignored.
    OTHER_KEYS = %w[decision coding_hours art_hours hours hours_start lapse_coding_hours ai_coding_hours ai_reason feedback title description changes_made repo_url demo_url key checked].freeze

    writes "edit_review_text", "Fix the review text of an approved ship",
           "Fixes the text a reviewer wrote on an APPROVED ship that is not yet in the Unified YSWS DB: technical_features, judgement (review_judgement) and deflation_reason. Send any subset: a field you leave out is kept. " \
           "Nothing else changes: not the hours, the verdict, the checklist, the hours start or the links. Once the ship is in the Unified YSWS DB its row is never edited (D-150), so this refuses it. " \
           "The ship is marked unsynced, so the corrected text goes out with its first Unified send. Every change is written to the admin log with the old and the new text. Tells nobody. " \
           "For a ship in review use save_review_draft. You can't edit your own ship, or one another admin has open. Answers { saved, message, changes, ship }.",
           { ship_id: { type: "integer", description: "The ship ID." },
             technical_features: { type: "string", description: "The specific technical features that explain the hours. Can't be empty." },
             judgement: { type: "string", description: "The reviewer's judgement (review_judgement). An empty string clears it." },
             deflation_reason: { type: "string", description: "Why the hours are below what the rules allow. Can't be emptied while the hours are below the claimed." } },
           required: %w[ship_id]

    def self.run(args, caller)
      ship = Ship.includes(:decided_by, project: :user).find(args[:ship_id])
      Guard.check!(ship, "review", caller)
      raise AdminMcp::Refused, "Only the review text can change here: technical_features, judgement and deflation_reason." if (args.keys.map(&:to_s) & OTHER_KEYS).any?

      changes = ship.fix_review_text!({ technical_features: args[:technical_features], review_judgement: args[:judgement], deflation_reason: args[:deflation_reason] }.compact, by: caller.user)
      return { saved: false, message: "Not saved: #{ship.errors.full_messages.to_sentence}", changes: {}, ship: AdminMcp::Present.ship(ship.reload) } if changes == false

      { saved: true, message: (changes.empty? ? "Nothing changed." : nil), changes:, ship: AdminMcp::Present.ship(ship.reload) }
    end
  end
end
