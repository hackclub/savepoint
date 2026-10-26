# One admin MCP tool call (D-046): who made it, with which token, which tool, and the record IDs its arguments name
# (`{ "ship_id" => 12 }`). Viewing as a participant (Admin::ImpersonationsController) is logged too, as the tool
# `impersonate` or `stop_impersonating` with no token, since it happens on the web. Written before the tool runs. It holds no free text, so nothing a participant wrote and no
# email ever lands here.
class AdminAuditEvent < ApplicationRecord
  belongs_to :user
  belongs_to :admin_token, optional: true

  scope :newest, -> { order(created_at: :desc, id: :desc) }
end
