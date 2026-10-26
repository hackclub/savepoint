# The tables and fields the sync writes, in Airtable's own field types. The sync
# (AirtableFields) and bin/rails airtable:provision both read this list, so a
# field is written only if provisioning makes it. The submission table's field
# names are the YSWS template's, the same ones playground writes.
module AirtableSchema
  ID_FIELD = "save_point_id"
  UNIFIED_FIELD = "Automation - YSWS Record ID"

  DATETIME = { dateFormat: { name: "iso" }, timeFormat: { name: "24hour" }, timeZone: "utc" }.freeze
  DATE = { dateFormat: { name: "iso" } }.freeze
  CHECKBOX = { icon: "check", color: "greenBright" }.freeze

  # [name, type, options]
  USERS = [
    [ ID_FIELD, "singleLineText" ], [ "Email", "email" ], [ "Name", "singleLineText" ], [ "First Name", "singleLineText" ],
    [ "Slack ID", "singleLineText" ], [ "Hack Club Auth ID", "singleLineText" ], [ "Hackatime ID", "singleLineText" ],
    [ "Verification Status", "singleLineText" ], [ "YSWS Eligible", "checkbox", CHECKBOX ],
    [ "Signed Up At", "dateTime", DATETIME ]
  ].freeze

  PROJECTS = [
    [ ID_FIELD, "singleLineText" ], [ "Name", "singleLineText" ], [ "Idea", "singleLineText" ], [ "User ID", "singleLineText" ],
    [ "Repo URL", "url" ], [ "Prize", "singleLineText" ], [ "Goal Hours", "number", { precision: 2 } ],
    [ "Hours Approved", "number", { precision: 2 } ], [ "Hours Spent", "number", { precision: 2 } ],
    [ "Pace Minutes", "number", { precision: 0 } ], [ "Build Time", "singleLineText" ], [ "Signed On", "date", DATE ],
    [ "Jame Gam", "checkbox", CHECKBOX ], [ "Hackatime Projects", "singleLineText" ], [ "Created At", "dateTime", DATETIME ]
  ].freeze

  ORDERS = [
    [ ID_FIELD, "singleLineText" ], [ "Project ID", "singleLineText" ], [ "Prize", "singleLineText" ],
    [ "Prize Name", "singleLineText" ], [ "Hours", "number", { precision: 2 } ], [ "Status", "singleLineText" ],
    [ "Ordered At", "dateTime", DATETIME ], [ "Created At", "dateTime", DATETIME ]
  ].freeze

  SUBMISSION = [
    [ ID_FIELD, "singleLineText" ], [ "Code URL", "url" ], [ "Playable URL", "url" ], [ "First Name", "singleLineText" ],
    [ "Last Name", "singleLineText" ], [ "Email", "email" ], [ "Screenshot", "multipleAttachments" ],
    [ "Description", "multilineText" ], [ "GitHub Username", "singleLineText" ], [ "Address (Line 1)", "singleLineText" ],
    [ "Address (Line 2)", "singleLineText" ], [ "City", "singleLineText" ], [ "State / Province", "singleLineText" ],
    [ "Country", "singleLineText" ], [ "ZIP / Postal Code", "singleLineText" ], [ "Birthday", "date", DATE ],
    [ "Optional - Override Hours Spent", "number", { precision: 2 } ],
    # The sync leaves this one empty and fills the separate fields below, as the handbook asks a small YSWS (D-030).
    [ "Optional - Override Hours Spent Justification", "multilineText" ],
    [ "Justification - Hackatime Project Name(s) + Date Range(s)", "multilineText" ],
    [ "Justification - Submitter Hackatime ID", "singleLineText" ],
    [ "Justification - Specific Technical Features", "multilineText" ],
    [ "Justification - Deflation Justification", "multilineText" ],
    [ "Justification - Additional Justification", "multilineText" ],
    [ "Justification - Alternate Tracking Method", "multilineText" ],
    [ "Optional - Override Duplicate Justification", "multilineText" ]
  ].freeze

  # config key => fields
  TABLES = { users: USERS, projects: PROJECTS, orders: ORDERS, ships: SUBMISSION }.freeze

  def self.field_names(key) = TABLES.fetch(key).map(&:first)

  # The fields as the meta API takes them.
  def self.field_defs(key)
    TABLES.fetch(key).map { |name, type, options| { name:, type: }.merge(options ? { options: } : {}) }
  end
end
