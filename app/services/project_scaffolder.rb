require "fileutils"

# Turns a template into a real directory tree on disk.
# Also used by projects:resync to add folders introduced into a template later.
class ProjectScaffolder
  def initialize(project)
    @project = project
    @template = project.template
  end

  def scaffold!
    FileUtils.mkdir_p(@project.root, mode: 0o770)
    created = []

    @template.folder_paths.each do |rel|
      next if rel == @template.library_dest # handled below
      abs = File.join(@project.root, rel)
      unless Dir.exist?(abs)
        FileUtils.mkdir_p(abs, mode: 0o770)
        created << rel
      end
    end

    install_library!
    created
  end

  # Frozen-per-project by default: the drawing you open in three years renders
  # the way it did when it was drawn. Switch to mode: link for one shared master.
  def install_library!
    src  = @template.library_source
    dest = File.join(@project.root, @template.library_dest)
    return if src.blank? || @template.library_dest.blank?

    unless Dir.exist?(src)
      Rails.logger.warn("library source missing: #{src}")
      return
    end

    case @template.library_mode
    when "copy"
      return if Dir.exist?(dest) && !Dir.empty?(dest)
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(File.join(src, "."), dest)
    when "link"
      return if File.symlink?(dest)
      FileUtils.rm_rf(dest)
      FileUtils.ln_s(src, dest)
    else
      raise ArgumentError, "unknown library mode #{@template.library_mode}"
    end
  end

  # Push an updated master library into this project (copy mode only).
  def sync_library!
    raise "project uses link mode; nothing to sync" if @template.library_mode == "link"
    dest = File.join(@project.root, @template.library_dest)
    FileUtils.mkdir_p(dest)
    FileUtils.cp_r(File.join(@template.library_source, "."), dest)
  end
end
