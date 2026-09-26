# A PM may add user/supervisor to their own project. Only an admin may create
# other PMs or admins. The role list itself is the enforcement point.
class MembershipsController < ApplicationController
  before_action :load_project

  def index
    @memberships = @project.memberships.includes(:user)
    @assignable = Permissions.assignable_roles(user: current_user, project: @project)
    @candidates = User.active.where.not(id: @project.user_ids)
  end

  def create
    role = params.require(:role)
    return head :forbidden unless allowed_roles.include?(role)

    membership = @project.memberships.new(user_id: params.require(:user_id), role: role)
    if membership.save
      audit!(project: @project, action: "member_add", path: "",
             detail: "#{membership.user.email} as #{role}")
      redirect_to project_memberships_path(@project), notice: "Added #{membership.user.name}."
    else
      redirect_to project_memberships_path(@project), alert: membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    membership = @project.memberships.find(params[:id])
    # A PM cannot remove another PM or an entry they could not have created.
    return head :forbidden unless allowed_roles.include?(membership.role)

    membership.destroy!
    audit!(project: @project, action: "member_remove", path: "",
           detail: "#{membership.user.email} (#{membership.role})")
    redirect_to project_memberships_path(@project), notice: "Removed #{membership.user.name}."
  end

  private

  def load_project
    @project = Project.find_by!(slug: params[:project_slug])
    # Non-members must not even see who is on a project.
    head :forbidden unless current_user.global_admin? || @project.role_for(current_user)
  end

  def allowed_roles
    Permissions.assignable_roles(user: current_user, project: @project)
  end
end
