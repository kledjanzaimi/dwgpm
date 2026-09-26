ENV["RAILS_ENV"] ||= "test"

require "tmpdir"
require "fileutils"

# Each run gets a throwaway storage root standing in for the file server.
ENV["STORAGE_ROOT"] = Dir.mktmpdir("dwgpm-storage")
ENV["UNC_TEMPLATE"] = '\\\\fileserver\\proj_%{slug}$'

# Template editor tests write templates; give them a copy of the real ones.
ENV["TEMPLATES_DIR"] = Dir.mktmpdir("dwgpm-templates")
FileUtils.cp(Dir[File.expand_path("../config/templates/*.yml", __dir__)], ENV["TEMPLATES_DIR"])

require_relative "../config/environment"
require "rails/test_help"

Minitest.after_run { FileUtils.rm_rf([ENV["STORAGE_ROOT"], ENV["TEMPLATES_DIR"]]) }

module ActiveSupport
  class TestCase
    # Tests share one storage root on disk, so they run in a single process.

    PASSWORD = "test-password-123"

    def create_user(name, admin: false)
      User.create!(name: name, email: "#{name.parameterize}@example.test",
                   password: PASSWORD, global_admin: admin)
    end

    def create_project(slug, creator:)
      project = Project.create!(name: slug.titleize, slug: slug, template_name: "standard_v1", created_by: creator)
      ProjectScaffolder.new(project).scaffold!
      project
    end

    def clear_storage!
      FileUtils.rm_rf(Dir.children(ENV["STORAGE_ROOT"]).map { |c| File.join(ENV["STORAGE_ROOT"], c) })
    end
  end
end

class ActionDispatch::IntegrationTest
  def sign_in(user)
    post login_path, params: { email: user.email, password: PASSWORD }
    assert_redirected_to root_path
  end
end
