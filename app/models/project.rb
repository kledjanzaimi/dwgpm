class Project < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :audit_logs, dependent: :nullify
  belongs_to :created_by, class_name: "User"

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]{1,62}\z/,
                             message: "must be lowercase letters, numbers and dashes" }
  validates :template_name, presence: true

  before_validation :derive_slug, on: :create

  # Routes are keyed on slug (`param: :slug`), so URLs must carry it too.
  def to_param = slug

  def template = FolderTemplate.load(template_name)

  # Absolute path on the server. The app writes here; nobody else does.
  def root
    File.join(ENV.fetch("STORAGE_ROOT"), slug)
  end

  # What the workstation uses to OPEN a drawing in place, so relative xrefs
  # resolve. UNC rather than a drive letter: no letter collisions when a user
  # works on several projects, and nothing to configure per machine.
  #   \\fileserver\proj_acme-123$\02_Drawings\DWG\plan.dwg
  def unc_path(rel_path = "")
    base = format(ENV.fetch("UNC_TEMPLATE"), slug: slug)
    return base if rel_path.to_s.empty?
    base + "\\" + rel_path.to_s.tr("/", "\\")
  end

  def share_name = format(ENV.fetch("SHARE_TEMPLATE", "proj_%{slug}$"), slug: slug)

  def role_for(user)
    return nil if user.nil?
    memberships.find_by(user_id: user.id)&.role
  end

  def project_managers
    users.merge(Membership.where(role: "project_manager"))
  end

  private

  def derive_slug
    self.slug = slug.presence || name.to_s.parameterize.first(63)
  end
end
