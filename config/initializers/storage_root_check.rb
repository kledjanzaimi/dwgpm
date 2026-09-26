# STORAGE_ROOT is a CIFS mount of the company's file server. If that mount is
# down, the path still exists — as an empty local directory on a disposable VM.
# The app would then scaffold projects onto local disk and report success, and
# users would upload real work into a folder nobody backs up.
#
# The marker file lives on the file server, so it can only be visible when the
# mount is genuinely up. See WINDOWS-DEPLOY.md.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  # `assets:precompile` inside `docker build` runs with no mounts and never
  # touches STORAGE_ROOT. The running container is still checked.
  next if ENV["SECRET_KEY_BASE_DUMMY"]

  root = ENV.fetch("STORAGE_ROOT")
  marker = File.join(root, ".dwgpm-root")

  next if File.exist?(marker)

  abort <<~MSG
    FATAL: #{marker} not found.

    The file server mount at #{root} is missing or empty. Refusing to start
    rather than write project data to local disk.

      mount | grep #{root}
  MSG
end
