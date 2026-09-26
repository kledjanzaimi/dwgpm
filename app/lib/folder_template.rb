# Loads a folder template YAML and answers: what rule applies to this path?
#
# nearest_rule walks a path upward until it finds a template-defined folder.
# That is what makes user-created subfolders inherit their parent's permissions
# with no extra configuration.
class FolderTemplate
  ROLES = %w[project_manager supervisor user].freeze

  NAME_FORMAT = /\A[a-z0-9][a-z0-9_-]{1,40}\z/

  class NotFound < StandardError; end

  attr_reader :name, :config

  # TEMPLATES_DIR lets tests work on a copy; Docker mounts the real folder.
  def self.dir
    Pathname.new(ENV.fetch("TEMPLATES_DIR") { Rails.root.join("config", "templates").to_s })
  end

  # Cached per template, invalidated on file mtime so edits apply without restart.
  def self.load(name)
    @cache ||= {}
    raise NotFound, "invalid template name #{name.inspect}" unless name.to_s.match?(NAME_FORMAT)
    path = dir.join("#{name}.yml")
    raise NotFound, "no template #{name}" unless File.exist?(path)

    mtime = File.mtime(path)
    cached = @cache[name]
    return cached[:tpl] if cached && cached[:mtime] == mtime

    tpl = new(name, YAML.safe_load_file(path))
    @cache[name] = { mtime: mtime, tpl: tpl }
    tpl
  end

  def initialize(name, config)
    @name = name
    @config = config
    @rules = {}
    Array(config["folders"]).each do |f|
      key = normalize(f["path"])
      @rules[key] = ROLES.index_with { |r| Array(f[r]).map(&:to_s) }
    end
  end

  # Every folder this template creates at scaffold time.
  def folder_paths
    @rules.keys.reject(&:empty?)
  end

  def library_source = config.dig("library", "source")
  def library_dest   = normalize(config.dig("library", "dest").to_s)
  def library_mode   = config.dig("library", "mode") || "copy"

  # Walk up: "02_Drawings/DWG/clientX/sub" -> tries that, then
  # "02_Drawings/DWG", then "02_Drawings". Returns nil at root (fail closed).
  def nearest_rule(rel_path)
    parts = normalize(rel_path).split("/")
    while parts.any?
      rule = @rules[parts.join("/")]
      return rule if rule
      parts.pop
    end
    nil
  end

  private

  def normalize(path)
    path.to_s.tr("\\", "/").split("/").reject { |s| s.empty? || s == "." }.join("/")
  end
end
