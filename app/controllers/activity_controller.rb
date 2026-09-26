# Read-only view of the audit log. Admins see everything at /activity; a
# project's managers (and admins) see that project's entries at
# /projects/:slug/activity. Nothing here can change the log (CLAUDE.md #11).
class ActivityController < ApplicationController
  PER_PAGE = 50

  before_action :load_scope

  def index
    logs = @scope.includes(:user, :project)
    logs = logs.where(user_id: params[:user_id]) if params[:user_id].present?
    logs = logs.where(action: params[:kind]) if params[:kind].present?
    logs = logs.where(project_id: params[:project_id]) if @project.nil? && params[:project_id].present?
    logs = logs.where(allowed: false) if params[:denied] == "1"
    if params[:q].present?
      term = "%#{AuditLog.sanitize_sql_like(params[:q].to_s)}%"
      logs = logs.where("audit_logs.path LIKE ? OR audit_logs.detail LIKE ?", term, term)
    end
    logs = logs.where(audit_logs: { id: ...params[:before].to_i }) if params[:before].present?

    # Newest first, paged by id so new entries never shift a page.
    page = logs.order(id: :desc).limit(PER_PAGE + 1).to_a
    @more = page.size > PER_PAGE
    @logs = page.first(PER_PAGE)

    @user_options = User.where(id: @scope.select(:user_id)).order(:name)
    @kinds = @scope.distinct.order(:action).pluck(:action)
    @project_options = Project.order(:name) if @project.nil?
  end

  private

  def load_scope
    if params[:project_slug]
      @project = Project.find_by!(slug: params[:project_slug])
      unless current_user.global_admin? || @project.role_for(current_user) == "project_manager"
        return head :forbidden
      end
      @scope = AuditLog.where(project: @project)
    else
      return head :forbidden unless current_user.global_admin?
      @scope = AuditLog.all
    end
  end
end
