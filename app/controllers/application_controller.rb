class ApplicationController < ActionController::Base
  before_action :require_login

  helper_method :current_user, :can?

  private

  def current_user
    @current_user ||= User.active.find_by(id: session[:user_id])
  end

  def require_login
    redirect_to login_path unless current_user
  end

  def require_admin
    head :forbidden unless current_user&.global_admin?
  end

  def can?(action, project, rel_path)
    Permissions.can?(user: current_user, project: project, action: action, rel_path: rel_path)
  end

  def audit!(project:, action:, path:, detail: nil, allowed: true)
    AuditLog.record!(
      user: current_user, project: project, action: action,
      path: path, ip: request.remote_ip, detail: detail, allowed: allowed
    )
  end
end
