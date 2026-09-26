# The whole authorization model, in one function.
#   (role, folder) -> {view, upload, delete}
# Admin is implicitly everything, everywhere. Everyone else gets exactly what
# the template YAML grants their role on the nearest defined ancestor folder.
module Permissions
  ACTIONS = %w[view upload delete].freeze

  def self.can?(user:, project:, action:, rel_path:)
    action = action.to_s
    return false unless ACTIONS.include?(action)
    return false if user.nil?
    return true if user.global_admin?

    role = project.role_for(user)
    return false if role.nil?

    # Any member may list the project root; entries are filtered individually.
    return true if action == "view" && rel_path.to_s.empty?

    rule = FolderTemplate.load(project.template_name).nearest_rule(rel_path)
    return false if rule.nil? # fail closed: undefined path grants nothing

    Array(rule[role]).include?(action)
  end

  # Can this user change membership on this project, and to which roles?
  def self.assignable_roles(user:, project:)
    return Membership::ROLES if user.global_admin?
    return %w[user supervisor] if project.role_for(user) == "project_manager"
    []
  end
end
