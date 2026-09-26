class Membership < ApplicationRecord
  ROLES = %w[user supervisor project_manager].freeze

  belongs_to :user
  belongs_to :project

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :project_id }
end
