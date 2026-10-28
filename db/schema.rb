# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_28_110100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_audit_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "admin_token_id"
    t.string "tool", null: false
    t.jsonb "ids", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["admin_token_id"], name: "index_admin_audit_events_on_admin_token_id"
    t.index ["created_at"], name: "index_admin_audit_events_on_created_at"
    t.index ["user_id"], name: "index_admin_audit_events_on_user_id"
  end

  create_table "admin_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_admin_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_admin_tokens_on_user_id"
  end

  create_table "buddy_pomodoros", force: :cascade do |t|
    t.integer "pair_id", null: false
    t.integer "started_by_id", null: false
    t.integer "minutes", null: false
    t.datetime "started_at", null: false
    t.datetime "joined_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pair_id"], name: "index_buddy_pomodoros_on_pair_id"
    t.index ["started_by_id"], name: "index_buddy_pomodoros_on_started_by_id"
  end

  create_table "claims", force: :cascade do |t|
    t.bigint "ship_id", null: false
    t.bigint "user_id", null: false
    t.string "stage", null: false
    t.datetime "heartbeat_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ship_id", "stage"], name: "index_claims_on_ship_id_and_stage", unique: true
    t.index ["ship_id"], name: "index_claims_on_ship_id"
    t.index ["user_id"], name: "index_claims_on_user_id"
  end

  create_table "coded_buckets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "bucket_at", null: false
    t.integer "seconds", default: 0, null: false
    t.integer "unconfirmed_seconds", default: 0, null: false
    t.integer "coding_seconds"
    t.index ["bucket_at"], name: "index_coded_buckets_on_bucket_at"
    t.index ["user_id", "bucket_at"], name: "index_coded_buckets_on_user_id_and_bucket_at", unique: true
    t.index ["user_id"], name: "index_coded_buckets_on_user_id"
  end

  create_table "extensions", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.text "reason", null: false
    t.string "status", default: "pending", null: false
    t.bigint "decided_by_id"
    t.datetime "decided_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["decided_by_id"], name: "index_extensions_on_decided_by_id"
    t.index ["project_id"], name: "index_extensions_on_project_id", unique: true
  end

  create_table "faq_reads", force: :cascade do |t|
    t.string "key", null: false
    t.integer "seconds", null: false
    t.datetime "created_at", null: false
    t.string "reader_id"
    t.index ["key", "created_at"], name: "index_faq_reads_on_key_and_created_at"
    t.index ["reader_id"], name: "index_faq_reads_on_reader_id"
  end

  create_table "metric_snapshots", force: :cascade do |t|
    t.date "day", null: false
    t.string "key", null: false
    t.float "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day", "key"], name: "index_metric_snapshots_on_day_and_key", unique: true
  end

  create_table "nps_responses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_id"
    t.string "source", null: false
    t.integer "score", null: false
    t.text "doing_well"
    t.text "improve"
    t.text "anything_else"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_nps_responses_on_created_at"
    t.index ["project_id"], name: "index_nps_responses_on_project_id"
    t.index ["user_id", "created_at"], name: "index_nps_responses_on_user_id_and_created_at"
    t.check_constraint "score >= 0 AND score <= 10", name: "nps_responses_score_0_to_10"
  end

  create_table "nudges", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "channel", default: "slack", null: false
    t.string "kind", null: false
    t.string "bucket"
    t.string "arm", null: false
    t.integer "variant"
    t.string "mood"
    t.text "text"
    t.text "mood_text"
    t.float "propensity"
    t.boolean "holdout", default: false, null: false
    t.string "token", null: false
    t.datetime "sent_at"
    t.boolean "delivered", default: false, null: false
    t.string "slack_channel"
    t.string "slack_ts"
    t.datetime "clicked_at"
    t.integer "clicks", default: 0, null: false
    t.datetime "opted_out_at"
    t.integer "reward"
    t.datetime "rewarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "built_on"
    t.boolean "stickers_promised", default: false, null: false
    t.datetime "stickers_earned_at"
    t.integer "ship_id"
    t.index ["ship_id"], name: "index_nudges_on_ship_id"
    t.index ["token"], name: "index_nudges_on_token", unique: true
    t.index ["user_id", "built_on"], name: "index_nudges_on_user_id_and_built_on"
    t.index ["user_id", "sent_at"], name: "index_nudges_on_user_id_and_sent_at"
    t.index ["user_id"], name: "index_nudges_on_user_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.decimal "hours", precision: 6, scale: 2, null: false
    t.string "status", default: "waiting", null: false
    t.bigint "ordered_by_id"
    t.datetime "ordered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "address"
    t.string "prize_key"
    t.text "recipient_name"
    t.datetime "synced_at"
    t.string "airtable_record_id"
    t.datetime "airtable_failed_at"
    t.string "theseus_letter_id"
    t.index ["ordered_by_id"], name: "index_orders_on_ordered_by_id"
    t.index ["project_id", "prize_key"], name: "index_orders_on_project_id_and_prize_key", unique: true, where: "((prize_key)::text <> 'stickers'::text)"
  end

  create_table "pairs", force: :cascade do |t|
    t.integer "first_project_id", null: false
    t.integer "second_project_id", null: false
    t.date "started_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["first_project_id"], name: "index_pairs_on_first_project_id", unique: true
    t.index ["second_project_id"], name: "index_pairs_on_second_project_id", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "idea", null: false
    t.integer "pace_minutes", null: false
    t.string "build_time", null: false
    t.date "signed_on", null: false
    t.string "repo_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "hackatime_projects", default: [], null: false
    t.boolean "repo_later", default: false, null: false
    t.boolean "party_queued", default: false, null: false
    t.string "name"
    t.string "buddy_code"
    t.boolean "buddy_invited", default: false, null: false
    t.boolean "buddy_skipped", default: false, null: false
    t.json "hackatime_baseline"
    t.boolean "hackatime_auto_linked", default: false, null: false
    t.integer "week_rank"
    t.date "week_rank_on"
    t.string "prize_key"
    t.boolean "jame_gam", default: false, null: false
    t.string "goal_reached_seen_key"
    t.datetime "synced_at"
    t.string "airtable_record_id"
    t.datetime "airtable_failed_at"
    t.integer "hackatime_seen_count"
    t.bigint "hackatime_seen_seconds"
    t.datetime "hackatime_seen_at"
    t.json "hackatime_baseline_seconds"
    t.datetime "hours_start_override"
    t.datetime "jame_gam_submitted_at"
    t.string "jame_gam_submission_id"
    t.string "jame_gam_review_status"
    t.datetime "first_coded_at"
    t.datetime "hackatime_picked_at"
    t.boolean "hackatime_link_confirmed", default: false, null: false
    t.index ["buddy_code"], name: "index_projects_on_buddy_code", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id", unique: true
  end

  create_table "rewards", force: :cascade do |t|
    t.integer "user_id"
    t.integer "pair_id"
    t.string "key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "announce_at"
    t.index ["key"], name: "index_rewards_on_desktop", unique: true, where: "((key)::text = 'desktop'::text)"
    t.index ["pair_id", "key"], name: "index_rewards_on_pair_id_and_key", unique: true
    t.index ["pair_id"], name: "index_rewards_on_pair_id"
    t.index ["user_id", "key"], name: "index_rewards_on_user_id_and_key", unique: true
    t.index ["user_id"], name: "index_rewards_on_user_id"
  end

  create_table "ship_send_backs", force: :cascade do |t|
    t.bigint "ship_id", null: false
    t.bigint "user_id", null: false
    t.text "reason", null: false
    t.jsonb "earlier_review", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["ship_id"], name: "index_ship_send_backs_on_ship_id"
    t.index ["user_id"], name: "index_ship_send_backs_on_user_id"
  end

  create_table "ships", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "repo_url", null: false
    t.string "demo_url", null: false
    t.json "hackatime_projects", default: [], null: false
    t.decimal "hours", precision: 6, scale: 2, default: "0.0", null: false
    t.string "status", default: "in_review", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "decided_by_id"
    t.datetime "decided_at"
    t.decimal "approved_hours", precision: 6, scale: 2
    t.text "changes_made"
    t.datetime "synced_at"
    t.string "airtable_record_id"
    t.datetime "airtable_failed_at"
    t.boolean "in_unified", default: false, null: false
    t.integer "ai_coding_seconds"
    t.integer "art_seconds"
    t.decimal "claimed_hours", precision: 6, scale: 2
    t.text "technical_features"
    t.text "deflation_reason"
    t.text "review_feedback"
    t.text "review_judgement"
    t.json "review_checklist", default: {}, null: false
    t.bigint "snapshot_edited_by_id"
    t.datetime "snapshot_edited_at"
    t.json "hackatime_seconds"
    t.bigint "reviewer_id"
    t.datetime "reviewed_at"
    t.decimal "review_coding_hours", precision: 6, scale: 2
    t.decimal "review_art_hours", precision: 6, scale: 2
    t.decimal "review_hours", precision: 6, scale: 2
    t.string "fraud_status"
    t.bigint "fraud_reviewer_id"
    t.datetime "fraud_reviewed_at"
    t.decimal "fraud_deduction_hours", precision: 6, scale: 2, default: "0.0", null: false
    t.text "fraud_notes"
    t.integer "lapse_seconds"
    t.decimal "lapse_coding_hours", precision: 6, scale: 2, default: "0.0", null: false
    t.decimal "reviewer_ai_coding_hours", precision: 6, scale: 2
    t.text "reviewer_ai_reason"
    t.bigint "superseded_by_id"
    t.index ["decided_by_id"], name: "index_ships_on_decided_by_id"
    t.index ["fraud_reviewer_id"], name: "index_ships_on_fraud_reviewer_id"
    t.index ["project_id"], name: "index_ships_on_project_id"
    t.index ["reviewer_id"], name: "index_ships_on_reviewer_id"
    t.index ["snapshot_edited_by_id"], name: "index_ships_on_snapshot_edited_by_id"
    t.index ["status"], name: "index_ships_on_status"
    t.index ["superseded_by_id"], name: "index_ships_on_superseded_by_id"
  end

  create_table "site_days", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "date", null: false
    t.datetime "created_at", null: false
    t.index ["date"], name: "index_site_days_on_date"
    t.index ["user_id", "date"], name: "index_site_days_on_user_id_and_date", unique: true
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_id"
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "streak_activities", force: :cascade do |t|
    t.integer "user_id", null: false
    t.date "activity_date", null: false
    t.integer "coded_seconds", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "unconfirmed_seconds", default: 0, null: false
    t.integer "coding_seconds"
    t.index ["user_id", "activity_date"], name: "index_streak_activities_on_user_id_and_activity_date", unique: true
    t.index ["user_id"], name: "index_streak_activities_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "hca_id", null: false
    t.string "email"
    t.string "name"
    t.string "slack_id"
    t.string "verification_status"
    t.boolean "ysws_eligible", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name"
    t.string "hackatime_uid"
    t.text "hackatime_access_token"
    t.integer "current_streak", default: 0, null: false
    t.datetime "streak_synced_at"
    t.string "timezone"
    t.date "streak_skip_used_on"
    t.datetime "slack_channels_joined_at"
    t.datetime "slack_muted_at"
    t.datetime "slack_dm_failed_at"
    t.string "slack_display_name"
    t.datetime "slack_dmed_at"
    t.text "address"
    t.text "phone_number"
    t.text "birthdate"
    t.string "slack_username"
    t.text "preferred_name"
    t.string "slack_avatar_url"
    t.datetime "slack_channels_failed_at"
    t.datetime "synced_at"
    t.string "airtable_record_id"
    t.datetime "airtable_failed_at"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_term"
    t.datetime "last_seen_at"
    t.string "last_seen_path"
    t.integer "onboarding_step_reached"
    t.datetime "onboarding_step_at"
    t.string "slack_dm_error"
    t.string "hackatime_trust_level"
    t.datetime "banned_at"
    t.text "ban_reason"
    t.datetime "hackatime_linked_at"
    t.jsonb "onboarding_step_times", default: {}, null: false
    t.index ["hackatime_uid"], name: "index_users_on_hackatime_uid", unique: true
    t.index ["hca_id"], name: "index_users_on_hca_id", unique: true
  end

  create_table "visits", force: :cascade do |t|
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_term"
    t.string "path", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_visits_on_created_at"
    t.index ["utm_source"], name: "index_visits_on_utm_source"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_audit_events", "admin_tokens"
  add_foreign_key "admin_audit_events", "users"
  add_foreign_key "admin_tokens", "users"
  add_foreign_key "buddy_pomodoros", "pairs"
  add_foreign_key "buddy_pomodoros", "projects", column: "started_by_id"
  add_foreign_key "claims", "ships"
  add_foreign_key "claims", "users"
  add_foreign_key "coded_buckets", "users"
  add_foreign_key "extensions", "projects"
  add_foreign_key "extensions", "users", column: "decided_by_id"
  add_foreign_key "nps_responses", "projects", on_delete: :nullify
  add_foreign_key "nps_responses", "users", on_delete: :cascade
  add_foreign_key "nudges", "users"
  add_foreign_key "orders", "projects"
  add_foreign_key "orders", "users", column: "ordered_by_id"
  add_foreign_key "pairs", "projects", column: "first_project_id"
  add_foreign_key "pairs", "projects", column: "second_project_id"
  add_foreign_key "projects", "users"
  add_foreign_key "rewards", "pairs"
  add_foreign_key "rewards", "users"
  add_foreign_key "ship_send_backs", "ships"
  add_foreign_key "ship_send_backs", "users"
  add_foreign_key "ships", "projects"
  add_foreign_key "ships", "ships", column: "superseded_by_id", on_delete: :nullify
  add_foreign_key "ships", "users", column: "decided_by_id"
  add_foreign_key "ships", "users", column: "fraud_reviewer_id"
  add_foreign_key "ships", "users", column: "reviewer_id"
  add_foreign_key "ships", "users", column: "snapshot_edited_by_id"
  add_foreign_key "site_days", "users", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "streak_activities", "users"
end
