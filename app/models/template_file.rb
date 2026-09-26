require "digest"
require "fileutils"

# One folder template YAML, as the admin UI edits it. This is the only code
# that writes to the templates folder; FolderTemplate stays the read side that
# Permissions uses. The YAML file remains the single source of truth.
class TemplateFile
  include ActiveModel::Model

  ROLES = FolderTemplate::ROLES
  ACTIONS = Permissions::ACTIONS
  LIBRARY_MODES = %w[copy link].freeze

  # Folder names must survive the Windows file server: no reserved characters,
  # no trailing dot or space, no "." / ".." segments.
  BAD_SEGMENT = /[\\:*?"<>|\x00-\x1f]|[. ]\z|\A\.{1,2}\z/

  attr_accessor :name, :folders, :library_source, :library_dest, :library_mode,
                :dwg_depth, :extra, :digest

  validates :name, format: { with: FolderTemplate::NAME_FORMAT,
                             message: "must be 2-41 lowercase letters, numbers, dashes or underscores" }
  validates :library_mode, inclusion: { in: LIBRARY_MODES }
  validate :folders_are_valid
  validate :library_is_valid

  def self.names
    Dir[FolderTemplate.dir.join("*.yml")].map { |p| File.basename(p, ".yml") }
                                         .grep(FolderTemplate::NAME_FORMAT).sort
  end

  def self.all = names.map { |n| find(n) }

  def self.path_for(name)
    raise FolderTemplate::NotFound, "invalid template name" unless name.to_s.match?(FolderTemplate::NAME_FORMAT)
    FolderTemplate.dir.join("#{name}.yml")
  end

  def self.exists?(name) = name.to_s.match?(FolderTemplate::NAME_FORMAT) && File.exist?(path_for(name))

  def self.find(name)
    path = path_for(name)
    raise FolderTemplate::NotFound, "no template #{name}" unless File.exist?(path)
    raw = File.read(path)
    new(name: name, digest: Digest::SHA256.hexdigest(raw), **from_config(YAML.safe_load(raw) || {}))
  end

  def self.from_config(config)
    {
      folders: Array(config["folders"]).map { |f| folder_hash(f["path"], f) },
      library_source: config.dig("library", "source"),
      library_dest: config.dig("library", "dest"),
      library_mode: config.dig("library", "mode") || "copy",
      dwg_depth: config["dwg_depth"],
      # Keys the UI does not know about are carried through untouched.
      extra: config.except("name", "library", "dwg_depth", "folders")
    }
  end

  def self.folder_hash(path, grants)
    ROLES.index_with { |r| Array(grants[r]).map(&:to_s) & ACTIONS }.merge("path" => normalize_path(path))
  end

  def self.normalize_path(path)
    path.to_s.tr("\\", "/").split("/").map(&:strip).reject { |s| s.empty? || s == "." }.join("/")
  end

  # A blank template: one folder the PM runs and everyone can read.
  def self.blank(name)
    new(name: name, library_mode: "copy", extra: {},
        folders: [folder_hash("01_Documents", "project_manager" => ACTIONS,
                                              "supervisor" => %w[view upload], "user" => %w[view])])
  end

  def persisted? = digest.present?
  def to_param = name
  def path = self.class.path_for(name)
  def projects = Project.where(template_name: name)
  def updated_at = File.exist?(path) ? File.mtime(path) : nil

  # Applies the editor form. Upload or delete without view is meaningless
  # (the entry would be invisible), so view is implied.
  def assign_form(params)
    rows = params[:folders].respond_to?(:values) ? params[:folders].values : Array(params[:folders])
    self.folders = rows.map { |row| self.class.folder_hash(row[:path], row) }
                       .reject { |f| f["path"].empty? }
    folders.each do |f|
      ROLES.each { |r| f[r] = ACTIONS & (f[r] | ["view"]) if (f[r] & %w[upload delete]).any? }
    end
    self.library_source = params[:library_source].to_s.strip.presence
    self.library_dest = self.class.normalize_path(params[:library_dest]).presence
    self.library_mode = params[:library_mode].to_s
    self
  end

  # Writes atomically, keeping the previous version in .history/. Refuses if
  # the file changed since this copy was read (another admin, or a hand edit).
  def save
    return false unless valid?

    if persisted? && File.exist?(path) && Digest::SHA256.hexdigest(File.read(path)) != digest
      errors.add(:base, "This template was changed by someone else since you opened it. Reload and apply your changes again.")
      return false
    end

    archive_current!
    yaml = to_yaml
    tmp = "#{path}.tmp-#{Process.pid}"
    File.write(tmp, yaml)
    File.rename(tmp, path)
    self.digest = Digest::SHA256.hexdigest(yaml)
    true
  end

  # Moves the file into .history rather than deleting it.
  def retire!
    raise ArgumentError, "template is used by projects" if projects.exists?
    archive_current!
    File.delete(path)
  end

  def archive_current!
    return unless File.exist?(path)
    dir = FolderTemplate.dir.join(".history", name)
    FileUtils.mkdir_p(dir)
    FileUtils.cp(path, dir.join("#{Time.current.utc.strftime('%Y%m%dT%H%M%S%6NZ')}.yml"))
  end

  def sorted_folders = folders.sort_by { |f| f["path"].split("/") }

  # Folders in tree order with their nearest listed ancestor ("" at the top)
  # and depth in that tree, so the editor can show paths relative to it.
  def tree
    paths = folders.map { |f| f["path"] }
    sorted_folders.map do |f|
      ancestors = paths.select { |p| f["path"].start_with?("#{p}/") }
      [f, ancestors.max_by(&:length).to_s, ancestors.size]
    end
  end

  # Human summary of what changed, for the flash message and the audit log.
  def changes_from(before)
    old = before.folders.index_by { |f| f["path"] }
    new = folders.index_by { |f| f["path"] }
    parts = []
    parts << "added #{(new.keys - old.keys).join(', ')}" if (new.keys - old.keys).any?
    parts << "removed #{(old.keys - new.keys).join(', ')}" if (old.keys - new.keys).any?
    changed = (old.keys & new.keys).reject { |p| old[p] == new[p] }
    parts << "changed permissions on #{changed.join(', ')}" if changed.any?
    lib = %i[library_source library_dest library_mode].reject { |a| before.public_send(a) == public_send(a) }
    parts << "changed library settings" if lib.any?
    parts.any? ? parts.join("; ") : "no changes"
  end

  def to_yaml
    out = +<<~HEAD
      ---
      # Folder template: structure + permissions in one place.
      # Managed from the admin UI (Templates); hand edits work too. Each saved
      # version is kept in config/templates/.history/.
      # New folders reach existing projects only after "Create missing folders"
      # in the UI, or: bin/rails projects:resync_all
      name: #{name}
    HEAD

    if library_source.present? || library_dest.present?
      out << "\nlibrary:\n"
      out << "  source: #{library_source.to_json}\n" if library_source.present?
      out << "  dest: #{library_dest.to_json}\n" if library_dest.present?
      out << "  mode: #{library_mode}\n"
    end

    unless dwg_depth.nil?
      out << "\n# DWG files live exactly #{dwg_depth} levels deep so relative xrefs resolve.\n"
      out << "# Changing this breaks drawings already on disk. See README.\n"
      out << "dwg_depth: #{Integer(dwg_depth)}\n"
    end

    out << "\n" << extra.to_yaml.delete_prefix("---\n") if extra.present?

    out << "\nfolders:\n"
    sorted_folders.each do |f|
      out << "  - path: #{f['path'].to_json}\n"
      ROLES.each { |r| out << "    #{r}: [#{f[r].join(', ')}]\n" }
      out << "\n"
    end
    out.rstrip + "\n"
  end

  private

  def folders_are_valid
    if folders.blank?
      errors.add(:base, "A template needs at least one folder.")
      return
    end

    folders.each do |f|
      bad = f["path"].split("/").find { |seg| seg.match?(BAD_SEGMENT) }
      errors.add(:base, "Folder \"#{f['path']}\" has an invalid name part \"#{bad}\".") if bad
      errors.add(:base, "Folder \"#{f['path']}\" is too long.") if f["path"].length > 200
    end

    # The file server is case-insensitive: "Drawings" and "drawings" are one folder.
    folders.group_by { |f| f["path"].downcase }.each_value do |same|
      errors.add(:base, "Folder \"#{same.first['path']}\" is listed more than once.") if same.size > 1
    end
  end

  def library_is_valid
    return if library_dest.blank?
    unless folders.to_a.any? { |f| f["path"] == library_dest }
      errors.add(:base, "The library folder \"#{library_dest}\" must be one of the template's folders.")
    end
    errors.add(:base, "Set a library source folder, or clear the library folder.") if library_source.blank?
  end
end
