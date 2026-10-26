# A ship as an admin can correct it (playground's snapshot editor): the title, description, what they changed and the two
# links, and the screenshots. Only this ship changes: its project keeps its own. Each edit records who and when
# (snapshot_edited_by, snapshot_edited_at), writes an AdminAuditEvent and clears synced_at, so the next Airtable sync sends
# the ship again.
#
# The screenshots are the ship's `screenshot` (the cover) followed by its `extra_screenshots`, in the order they were
# attached. A new order moves the attachments between those two names and stamps their created_at, so no blob is copied
# or purged, and every reader of `ship.screenshot` still gets the cover.
class Ship::Snapshot
  include ActiveModel::Model
  include ActiveModel::Attributes

  FIELDS = %w[title description changes_made repo_url demo_url].freeze
  MAX_SCREENSHOTS = 6

  attribute :title, :string
  attribute :description, :string
  attribute :changes_made, :string
  attribute :repo_url, :string
  attribute :demo_url, :string

  # Ship's own message when an edit goes wrong, for the page and the JSON answers.
  class Refused < StandardError; end

  attr_reader :ship

  def initialize(ship)
    @ship = ship
    super(FIELDS.index_with { ship[it] })
  end

  def edited_by = ship.snapshot_edited_by
  def edited_at = ship.snapshot_edited_at

  # The admin can't edit their own ship.
  def own?(admin) = ship.project.user_id == admin.id

  # The cover first, then the rest in order. Reads the database each time, so it is right after any edit.
  def screenshots
    ship.association(:screenshot_attachment).reload
    [ ship.screenshot_attachment, *ship.extra_screenshots_attachments.reload.sort_by { [ it.created_at, it.id ] } ].compact
  end

  # Saves the fields that differ. True when saved, nil when nothing changed, false when a changed field is invalid
  # (the errors are on this object, what was typed stays in it, and the ship is left as it was). A field that was
  # already wrong before and isn't touched doesn't block the edit.
  def update(params, by:)
    typed = params.to_h.stringify_keys.slice(*FIELDS).transform_values { it.to_s }
    assign_attributes(typed)
    ship.assign_attributes(attributes.slice(*FIELDS.select { typed.key?(it) }))
    changed = ship.changes.keys & FIELDS
    if changed.empty?
      ship.restore_attributes
      return nil
    end

    ship.valid?
    ship.errors.each { errors.add(it.attribute, it.message) if changed.include?(it.attribute.to_s) }
    if errors.any?
      ship.restore_attributes
      return false
    end

    ship.transaction do
      ship.save!(validate: false)
      record(by, "edit_ship")
    end
    true
  end

  # Adds a screenshot at the end, or with replace: (an attachment id) takes that one's place. The file is checked like
  # a participant's: a still PNG, JPEG or WebP under 5 MB.
  def add_screenshot(file, by:, replace: nil)
    ship.with_lock do
      current = screenshots
      target = replace.presence && (current.find { it.id.to_s == replace.to_s } or raise Refused, "That screenshot is gone. Reload the page.")
      raise Refused, "A ship holds up to #{MAX_SCREENSHOTS} screenshots. Remove one to add another." if !target && current.size >= MAX_SCREENSHOTS

      blob = store(file)
      if target
        old = target.blob
        target.update!(blob:)
        forget(old)
        record(by, "replace_ship_screenshot")
        target
      else
        attachment = ship.extra_screenshots.attach(blob).then { ship.extra_screenshots_attachments.reload.find { it.blob_id == blob.id } }
        record(by, "add_ship_screenshot")
        attachment
      end
    end
  end

  # A ship keeps at least one: it can't be approved without. Removing the cover promotes the next one.
  def remove_screenshot(id, by:)
    ship.with_lock do
      current = screenshots
      gone = current.find { it.id.to_s == id.to_s } or raise Refused, "That screenshot is gone. Reload the page."
      raise Refused, "A ship keeps at least one screenshot. Add another before removing this one." if current.size == 1

      blob = gone.blob
      gone.delete
      arrange(current.reject { it.id == gone.id }.map(&:id))
      forget(blob)
      record(by, "remove_ship_screenshot")
    end
  end

  # The screenshots in a new order, by attachment id: the first becomes the cover. The ids must be exactly the ship's.
  def order_screenshots(ids, by:)
    ids = Array(ids).map(&:to_i)
    ship.with_lock do
      raise Refused, "The screenshots changed. Reload the page." unless ids.uniq.sort == screenshots.map(&:id).sort

      arrange(ids)
      record(by, "order_ship_screenshots")
    end
  end

  private
    # The first is the cover (name "screenshot"), the others follow it in order (created_at a millisecond apart).
    def arrange(ids)
      base = Time.current
      ActiveStorage::Attachment.transaction do
        ids.each_with_index do |id, index|
          ActiveStorage::Attachment.where(id:, record_type: "Ship", record_id: ship.id)
                                   .update_all(name: index.zero? ? "screenshot" : "extra_screenshots", created_at: base + (index * 0.001))
        end
      end
    end

    # The file as a blob, if it's an image we accept. Checked before it is stored.
    def store(file)
      raise Refused, "Choose an image first." unless file.respond_to?(:read) && file.respond_to?(:size)
      raise Refused, "Set a new screenshot under 5 MB." if file.size > Project::SCREENSHOT_MAX_SIZE

      type = Marcel::MimeType.for(file, name: file.original_filename)
      file.rewind
      raise Refused, "Set a still screenshot as a PNG, JPEG or WebP, not a GIF." unless Project::SCREENSHOT_TYPES.include?(type)

      ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename, content_type: type)
    end

    # A file that left the ship goes only when nothing else (the project, an earlier ship) shows it.
    def forget(blob) = (blob.purge_later if blob.attachments.none?)

    def record(by, tool)
      ship.update_columns(snapshot_edited_by_id: by.id, snapshot_edited_at: Time.current)
      ship.mark_unsynced
      AdminAuditEvent.create!(user: by, tool:, ids: { "ship_id" => ship.id })
    end
end
