# Path traversal is THE hole in every file manager. Nothing touches the
# filesystem without passing through here first.
#
# realpath also resolves symlinks, which closes the "symlink out of the root"
# variant that a simple string prefix check would miss.
module SafePath
  class Error < StandardError; end

  # Returns an absolute Pathname guaranteed to sit inside project_root.
  # allow_missing: true for upload/mkdir targets that don't exist yet.
  def self.resolve(project_root, rel_path, allow_missing: false)
    root = Pathname.new(project_root).realpath
    cleaned = rel_path.to_s.tr("\\", "/").delete_prefix("/")
    raise Error, "null byte in path" if cleaned.include?("\0")

    candidate = root.join(cleaned)

    real =
      begin
        candidate.realpath
      rescue Errno::ENOENT
        raise Error, "path does not exist" unless allow_missing
        # Parent must exist and be real; basename is the new entry.
        parent = candidate.dirname.realpath
        parent.join(candidate.basename)
      end

    unless real == root || real.to_s.start_with?(root.to_s + File::SEPARATOR)
      raise Error, "path escapes project root"
    end

    real
  end

  # Path relative to the project root, "" for the root itself.
  def self.relative(project_root, abs)
    root = Pathname.new(project_root).realpath
    Pathname.new(abs).relative_path_from(root).to_s.sub(/\A\.\z/, "")
  end
end
