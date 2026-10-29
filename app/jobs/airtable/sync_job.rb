# The rolling copy of Postgres rows to the program base (D-027).
# Every minute, for each table, it upserts the 10 rows with the oldest
# synced_at, never-synced rows first. A change to a row sets synced_at back to
# nil, so the row goes next. Submission rows are different: a ship is sent only
# when synced_at is nil, so a reviewer's edits in Airtable stay, and it never
# overwrites a row the Unified YSWS DB has taken. Off unless AIRTABLE_SYNC=1.
#
# A table that fails does not stop the others. When a batch request fails, each
# row goes alone. A row that still fails waits an hour (airtable_failed_at) and is
# not stamped synced. A row that changed while the batch was in flight is not
# stamped either. The log holds a row id and Airtable's error type, never a value.
module Airtable
  class SyncJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: "airtable-sync" if respond_to?(:limits_concurrency)

    BATCH = 10
    FAILED_WAIT = 1.hour
    ID = AirtableSchema::ID_FIELD

    def perform
      config = Rails.application.config_for(:airtable)
      return unless config[:enabled]

      @client = AirtableClient.new
      @tables = config[:tables]
      # Record calls use the submission table's id, so a rename does not break the sync.
      @ship_table = config[:submission_table_id].presence || @tables[:ships]
      guarded(:users) { sync(User.all, @tables[:users], "user-") { AirtableFields.user(it) } }
      guarded(:projects) { sync(Project.includes(:user, :ships, :orders), @tables[:projects], "project-") { AirtableFields.project(it) } }
      guarded(:orders) { sync(Order.includes(project: :user), @tables[:orders], "order-") { AirtableFields.order(it) } }
      guarded(:ships) { sync_ships }
    end

    private

    def guarded(table)
      yield
    rescue StandardError => e
      Rails.logger.warn("airtable sync: #{table} stopped with #{e.class}")
    end

    def due(scope)
      table = scope.klass.table_name
      scope.where("#{table}.airtable_failed_at IS NULL OR #{table}.airtable_failed_at < ?", FAILED_WAIT.ago)
    end

    def stale(scope) = scope.order(Arel.sql("#{scope.klass.table_name}.synced_at ASC NULLS FIRST")).limit(BATCH).to_a

    def sync(scope, table, prefix, read_at: Time.current, rows: nil, &fields)
      rows ||= stale(due(scope))
      return if rows.empty?
      done, failed = push(table, rows, prefix, &fields)
      settle(rows.first.class, done, failed, read_at)
    end

    # Only approved ships cross, only when marked unsynced, and never a row the Unified YSWS DB has taken.
    def sync_ships
      read_at = Time.current
      scope = Ship.approved.where(in_unified: false, synced_at: nil).includes(:screenshot_attachment, project: :user)
      ships = stale(due(scope))
      return if ships.empty?
      begin
        existing = @client.find_by(@ship_table, ID, ships.map { "ship-#{it.id}" })
      rescue AirtableClient::Error => e
        Rails.logger.warn("airtable sync: ship lookup failed, #{e.message}")
        return settle(Ship, [], ships, read_at)
      end
      taken, fresh = ships.partition { existing.dig("ship-#{it.id}", "fields", AirtableSchema::UNIFIED_FIELD).present? }
      Ship.where(id: taken.map(&:id)).update_all(in_unified: true)
      # D-111: the row Airtable has already is read, so a deflation sentence the ship no longer has is cleared rather than left (AirtableFields.clearing_stale_deflation).
      sync(scope, @ship_table, "ship-", read_at:, rows: fresh) { AirtableFields.clearing_stale_deflation(AirtableFields.ship(it), existing["ship-#{it.id}"]) }
    end

    # Upserts the rows. Returns [rows done, rows failed]. A failed batch is tried one row at a time.
    def push(table, rows, prefix)
      built, failed = [], []
      rows.each do |row|
        built << [ row, yield(row) ]
      rescue StandardError => e
        failed << row
        Rails.logger.warn("airtable sync: #{prefix}#{row.id} could not be built, #{e.class}")
      end
      done, records = [], {}
      begin
        records = @client.upsert(table, built.map(&:last), merge_on: ID) if built.any?
        done = built.map(&:first)
      rescue AirtableClient::Error => e
        log_failure(prefix, built.first.first, e) if built.size == 1
        failed << built.first.first if built.size == 1
        built.each do |row, fields|
          next if built.size == 1
          records.merge!(@client.upsert(table, [ fields ], merge_on: ID))
          done << row
        rescue AirtableClient::Error => single
          failed << row
          log_failure(prefix, row, single)
        end
      end
      rows.first.class.then do |klass|
        records.each { |id, record| klass.where(id: id.delete_prefix(prefix)).update_all(airtable_record_id: record["id"]) }
      end
      [ done, failed ]
    end

    def log_failure(prefix, row, error) = Rails.logger.warn("airtable sync: #{prefix}#{row.id} failed, #{error.message}")

    # Stamps rows that went through and did not change since the read. Marks the failed ones.
    def settle(klass, done, failed, read_at)
      klass.where(id: done.map(&:id)).where("updated_at <= ?", read_at).update_all(synced_at: Time.current, airtable_failed_at: nil)
      klass.where(id: failed.map(&:id)).update_all(airtable_failed_at: Time.current)
    end
  end
end
