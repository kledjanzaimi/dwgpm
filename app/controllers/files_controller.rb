# Every action here follows the same mandatory pipeline:
#   resolve (confine to root) -> authorize (can?) -> act -> audit
# Do not add an action that skips a step.
class FilesController < ApplicationController
  before_action :load_project
  before_action :resolve_path

  rescue_from SafePath::Error do |e|
    audit!(project: @project, action: "reject", path: params[:path], detail: e.message, allowed: false)
    head :bad_request
  end

  # Browse a folder. Entries the user cannot view are not listed at all.
  def index
    return head :forbidden unless can?("view", @project, @rel)
    return head :not_found unless File.directory?(@abs)

    @entries = Dir.children(@abs).sort.filter_map do |name|
      child_rel = @rel.empty? ? name : "#{@rel}/#{name}"
      next unless can?("view", @project, child_rel)
      abs = File.join(@abs, name)
      {
        name: name,
        rel: child_rel,
        dir: File.directory?(abs),
        dwg: File.extname(name).downcase == ".dwg",
        size: File.directory?(abs) ? nil : File.size(abs),
        mtime: File.mtime(abs)
      }
    end.sort_by { |e| [e[:dir] ? 0 : 1, e[:name].downcase] }

    @can_upload = can?("upload", @project, @rel)
    @can_delete = can?("delete", @project, @rel)
  end

  # DWG: hand back the UNC path instead of the bytes. The drawing must be
  # opened from its real position in the tree or its relative xrefs break.
  def locate
    return head :forbidden unless can?("view", @project, @rel)
    return head :not_found unless File.file?(@abs)

    audit!(project: @project, action: "locate", path: @rel)
    render json: { path: @project.unc_path(@rel) }
  end

  # Everything that is not a DWG streams through the app as a normal download.
  def download
    return head :forbidden unless can?("view", @project, @rel)
    return head :not_found unless File.file?(@abs)

    audit!(project: @project, action: "download", path: @rel)
    send_file @abs, disposition: "attachment"
  end

  def upload
    return head :forbidden unless can?("upload", @project, @rel)

    uploaded = params.require(:file)
    name = sanitize_filename(uploaded.original_filename)
    target = SafePath.resolve(@project.root, File.join(@rel, name), allow_missing: true)

    if File.exist?(target) && !can?("delete", @project, @rel)
      # Overwriting is a destructive act; require delete rather than upload.
      audit!(project: @project, action: "upload", path: @rel, detail: "overwrite denied: #{name}", allowed: false)
      return redirect_back fallback_location: project_files_path(@project, path: @rel),
                           alert: "#{name} already exists and you cannot replace it."
    end

    File.open(target, "wb") { |f| IO.copy_stream(uploaded.tempfile, f) }
    audit!(project: @project, action: "upload", path: SafePath.relative(@project.root, target))
    redirect_back fallback_location: project_files_path(@project, path: @rel), notice: "Uploaded #{name}."
  end

  def mkdir
    return head :forbidden unless can?("upload", @project, @rel)

    name = sanitize_filename(params.require(:name))
    target = SafePath.resolve(@project.root, File.join(@rel, name), allow_missing: true)
    FileUtils.mkdir_p(target, mode: 0o770)

    audit!(project: @project, action: "mkdir", path: SafePath.relative(@project.root, target))
    redirect_back fallback_location: project_files_path(@project, path: @rel), notice: "Created #{name}."
  end

  def destroy
    parent = @rel.split("/")[0..-2].join("/")
    return head :forbidden unless can?("delete", @project, parent)
    return head :forbidden if template_folder?(@rel) # never delete the scaffold

    detail = File.directory?(@abs) ? "directory (#{Dir.children(@abs).size} entries)" : "file"
    FileUtils.rm_rf(@abs)

    audit!(project: @project, action: "delete", path: @rel, detail: detail)
    redirect_to project_files_path(@project, path: parent), notice: "Deleted #{File.basename(@rel)}."
  end

  private

  def load_project
    @project = Project.find_by!(slug: params[:project_slug])
    head :forbidden unless current_user.global_admin? || @project.role_for(current_user)
  end

  def resolve_path
    @rel = params[:path].to_s
    @abs = SafePath.resolve(@project.root, @rel, allow_missing: false)
    @rel = SafePath.relative(@project.root, @abs)
  end

  def template_folder?(rel)
    @project.template.folder_paths.include?(rel)
  end

  def sanitize_filename(name)
    cleaned = File.basename(name.to_s.tr("\\", "/")).strip
    raise SafePath::Error, "invalid filename" if cleaned.empty? || cleaned.start_with?(".")
    cleaned
  end
end
