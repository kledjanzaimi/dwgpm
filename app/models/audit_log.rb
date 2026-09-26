# Append-only. Corporate clients will ask "who deleted this?" — this answers it.
class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :project, optional: true

  def self.record!(user:, project:, action:, path:, ip:, detail: nil, allowed: true)
    create!(
      user: user, project: project, action: action.to_s,
      path: path.to_s, ip: ip, detail: detail, allowed: allowed
    )
  end

  def readonly? = persisted?
end
