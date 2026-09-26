# Admin editor for config/templates/*.yml. The YAML stays the single source of
# truth (CLAUDE.md #9): this controller only reads and writes those files.
# Permission edits apply to every project on the template at the next request.
class TemplatesController < ApplicationController
  before_action :require_admin
  before_action :load_template, only: %i[edit update destroy resync]

  rescue_from FolderTemplate::NotFound do
    redirect_to templates_path, alert: "That template does not exist."
  end

  def index
    @templates = TemplateFile.all
    @project_counts = Project.group(:template_name).count
  end

  def new
    @name = params[:from].present? ? "#{params[:from]}_copy" : ""
    @sources = TemplateFile.names
  end

  # Starts a template from a copy of another, or from a blank one.
  def create
    name = params[:name].to_s.strip
    if TemplateFile.exists?(name)
      return redirect_to new_template_path(from: params[:from]), alert: "A template named #{name} already exists."
    end

    @template =
      if params[:from].present?
        TemplateFile.find(params[:from]).tap { |t| t.name = name; t.digest = nil }
      else
        TemplateFile.blank(name)
      end

    if @template.save
      audit!(project: nil, action: "template_create", path: template_rel,
             detail: params[:from].present? ? "copied from #{params[:from]}" : "blank")
      redirect_to edit_template_path(@template), notice: "Created template #{name}."
    else
      redirect_to new_template_path(from: params[:from]), alert: @template.errors.full_messages.to_sentence
    end
  end

  def edit
  end

  def update
    before = TemplateFile.find(@template.name)
    @template.digest = params.dig(:template, :digest)
    @template.assign_form(params.require(:template))

    if @template.save
      summary = @template.changes_from(before)
      audit!(project: nil, action: "template_update", path: template_rel, detail: summary)
      redirect_to edit_template_path(@template), notice: "Saved: #{summary}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @template.projects.exists?
      return redirect_to templates_path, alert: "#{@template.name} is used by projects and cannot be deleted."
    end

    @template.retire!
    audit!(project: nil, action: "template_delete", path: template_rel)
    redirect_to templates_path, notice: "Deleted #{@template.name}. A copy is kept in config/templates/.history/."
  end

  # Creates folders added to the template in every project that uses it.
  def resync
    created = @template.projects.where(archived_at: nil).sum { |p| ProjectScaffolder.new(p).scaffold!.size }
    audit!(project: nil, action: "template_resync", path: template_rel, detail: "#{created} folders created")
    redirect_to edit_template_path(@template),
                notice: created.zero? ? "All projects already have every folder." : "Created #{created} missing folders."
  end

  private

  def load_template
    @template = TemplateFile.find(params[:name])
    @projects = @template.projects.order(:name)
  end

  def template_rel = "config/templates/#{@template.name}.yml"
end
