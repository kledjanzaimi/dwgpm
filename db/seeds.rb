# Development data: one account per role and a scaffolded demo project, so
# every permission path can be tried by hand. Production uses `admin:seed`.
#
#   bin/rails db:seed        (idempotent; also runs on a fresh `bin/setup`)
#
# All accounts share DEV_PASSWORD below. Sign in at http://localhost:3000.
unless Rails.env.development?
  puts "db/seeds.rb only seeds development. Use `bin/rails admin:seed` in production."
  return
end

DEV_PASSWORD = "dev-password-123"

accounts = {
  admin:      { name: "Ada Admin",      email: "admin@dev.test",      global_admin: true },
  pm:         { name: "Pam Manager",    email: "pm@dev.test" },
  supervisor: { name: "Sam Supervisor", email: "supervisor@dev.test" },
  user:       { name: "Uma User",       email: "user@dev.test" },
  outsider:   { name: "Oscar Outsider", email: "outsider@dev.test" }
}.transform_values do |attrs|
  User.find_or_create_by!(email: attrs[:email]) do |u|
    u.assign_attributes(attrs.merge(password: DEV_PASSWORD))
  end
end

project = Project.find_or_create_by!(slug: "demo-bridge") do |p|
  p.name = "Demo Bridge"
  p.template_name = "standard_v1"
  p.created_by = accounts[:admin]
end

{ pm: "project_manager", supervisor: "supervisor", user: "user" }.each do |who, role|
  project.memberships.find_or_create_by!(user: accounts[who]) { |m| m.role = role }
end

ProjectScaffolder.new(project).scaffold!

# A couple of files so the browser has something to show.
{
  "02_Drawings/DWG/site-plan.dwg" => "placeholder drawing",
  "01_Incoming/client-brief.txt"  => "Client brief placeholder.\n",
  "00_Admin/contract.txt"         => "Only PMs and supervisors can see this.\n"
}.each do |rel, body|
  path = File.join(project.root, rel)
  File.write(path, body) unless File.exist?(path)
end

puts "Seeded #{User.count} users and project '#{project.slug}' at #{project.root}"
puts "Accounts: #{accounts.values.map(&:email).join(', ')} (password: see DEV_PASSWORD in db/seeds.rb)"
