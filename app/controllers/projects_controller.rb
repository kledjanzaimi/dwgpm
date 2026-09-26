class ProjectsController < ApplicationController
  before_action :require_admin, only: %i[new create]

  def index
    @projects = current_user.global_admin? ? Project.order(:name) : current_user.projects.order(:name)
  end

  def new
    @project = Project.new(template_name: "standard_v1")
    @project_managers = User.active.order(:name)
  end

  # Admin creates a project: record it, then scaffold the template on disk.
  def create
    @project = Project.new(project_params.merge(created_by: current_user))

    ActiveRecord::Base.transaction do
      @project.save!
      if params[:project_manager_id].present?
        @project.memberships.create!(user_id: params[:project_manager_id], role: "project_manager")
      end
      ProjectScaffolder.new(@project).scaffold!
    end

    audit!(project: @project, action: "project_create", path: "", detail: @project.template_name)
    redirect_to project_files_path(@project), notice: "Created #{@project.name}."
  rescue ActiveRecord::RecordInvalid
    @project_managers = User.active.order(:name)
    render :new, status: :unprocessable_entity
  end

  private

  def project_params
    params.require(:project).permit(:name, :slug, :template_name)
  end
end
