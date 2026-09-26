namespace :projects do
  desc "Create folders added to a template after the project was scaffolded"
  task :resync, [:slug] => :environment do |_t, args|
    project = Project.find_by!(slug: args[:slug])
    created = ProjectScaffolder.new(project).scaffold!
    puts created.any? ? "#{project.slug}: added #{created.join(', ')}" : "#{project.slug}: up to date"
  end

  desc "Resync every project (permission edits apply instantly; folders need this)"
  task resync_all: :environment do
    Project.where(archived_at: nil).find_each do |project|
      created = ProjectScaffolder.new(project).scaffold!
      puts "#{project.slug}: #{created.any? ? created.join(', ') : 'up to date'}"
    end
  end

  desc "Push the master library into one project (copy mode)"
  task :sync_library, [:slug] => :environment do |_t, args|
    project = Project.find_by!(slug: args[:slug])
    ProjectScaffolder.new(project).sync_library!
    puts "#{project.slug}: library updated"
  end

  desc "Verify every project root exists and matches its template"
  task check: :environment do
    Project.find_each do |project|
      missing = project.template.folder_paths.reject { |f| Dir.exist?(File.join(project.root, f)) }
      status = missing.empty? ? "ok" : "MISSING #{missing.join(', ')}"
      puts format("%-24s %s", project.slug, status)
    end
  end
end

namespace :admin do
  desc "Create the first administrator"
  task seed: :environment do
    email = ENV.fetch("SEED_ADMIN_EMAIL")
    User.find_or_create_by!(email: email) do |u|
      u.name = ENV.fetch("SEED_ADMIN_NAME", "Administrator")
      u.password = ENV.fetch("SEED_ADMIN_PASSWORD")
      u.global_admin = true
    end
    puts "admin ready: #{email}"
  end
end
