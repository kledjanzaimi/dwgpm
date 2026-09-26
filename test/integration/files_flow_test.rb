require "test_helper"

class FilesFlowTest < ActionDispatch::IntegrationTest
  setup do
    clear_storage!
    @admin = create_user("Admin", admin: true)
    @pm = create_user("Pam Manager")
    @user = create_user("Uma User")
    @outsider = create_user("Oscar Outsider")
  end

  def make_project
    project = create_project("acme-123", creator: @admin)
    project.memberships.create!(user: @pm, role: "project_manager")
    project.memberships.create!(user: @user, role: "user")
    project
  end

  test "pages require login" do
    get projects_path
    assert_redirected_to login_path
  end

  test "wrong password is refused and audited" do
    post login_path, params: { email: @user.email, password: "nope" }
    assert_response :unprocessable_entity
    assert AuditLog.where(action: "login", allowed: false).exists?
  end

  test "disabled users cannot sign in" do
    @user.update!(disabled_at: Time.current)
    post login_path, params: { email: @user.email, password: PASSWORD }
    assert_response :unprocessable_entity
  end

  test "admin creates a project and its folders appear on disk" do
    sign_in @admin
    post projects_path, params: { project: { name: "Bridge Works", slug: "", template_name: "standard_v1" },
                                  project_manager_id: @pm.id }
    project = Project.find_by!(slug: "bridge-works")
    assert_redirected_to project_files_path(project)
    assert Dir.exist?(File.join(project.root, "02_Drawings/DWG"))
    assert_equal "project_manager", project.role_for(@pm)
  end

  test "non-admins cannot create projects" do
    sign_in @pm
    get new_project_path
    assert_response :forbidden
  end

  test "a user only sees the folders their role may view" do
    project = make_project
    sign_in @user
    get project_files_path(project)
    assert_response :success
    assert_includes response.body, "01_Incoming"
    assert_not_includes response.body, "00_Admin"

    get project_files_path(project, path: "00_Admin")
    assert_response :forbidden
  end

  test "upload goes through permissions and lands in the audit log" do
    project = make_project
    sign_in @user
    file = Rack::Test::UploadedFile.new(StringIO.new(+"drawing"), "application/octet-stream",
                                        original_filename: "plan.dwg")
    post project_upload_files_path(project, path: "02_Drawings/DWG"), params: { file: file }
    assert File.exist?(File.join(project.root, "02_Drawings/DWG/plan.dwg"))
    assert AuditLog.where(action: "upload", path: "02_Drawings/DWG/plan.dwg", user: @user).exists?

    # Users may view 03_Output but not upload there.
    post project_upload_files_path(project, path: "03_Output"), params: { file: file }
    assert_response :forbidden
  end

  test "downloads bypass Turbo so each one is a single request" do
    project = make_project
    File.write(File.join(project.root, "01_Incoming/brief.txt"), "x")
    sign_in @user
    get project_files_path(project, path: "01_Incoming")
    assert_select "a[href$='/brief.txt/download'][data-turbo='false'][download]"

    get project_download_files_path(project, path: "01_Incoming/brief.txt")
    assert_response :success
    assert_equal 1, AuditLog.where(action: "download", path: "01_Incoming/brief.txt").count
  end

  test "DWGs are located by UNC path, not downloaded" do
    project = make_project
    File.write(File.join(project.root, "02_Drawings/DWG/plan.dwg"), "x")
    sign_in @user
    get project_locate_files_path(project, path: "02_Drawings/DWG/plan.dwg"), as: :json
    assert_equal '\\\\fileserver\\proj_acme-123$\\02_Drawings\\DWG\\plan.dwg', response.parsed_body["path"]
  end

  test "users cannot delete, and template folders are never deleted" do
    project = make_project
    File.write(File.join(project.root, "01_Incoming/a.txt"), "x")

    sign_in @user
    delete project_file_path(project, path: "01_Incoming/a.txt")
    assert_response :forbidden

    sign_in @pm
    delete project_file_path(project, path: "01_Incoming/a.txt")
    assert_not File.exist?(File.join(project.root, "01_Incoming/a.txt"))
    delete project_file_path(project, path: "02_Drawings/DWG")
    assert_response :forbidden
  end

  test "path traversal is rejected and audited" do
    project = make_project
    sign_in @user
    get project_files_path(project, path: "01_Incoming/../../..")
    assert_response :bad_request
    assert AuditLog.where(action: "reject", allowed: false).exists?
  end

  test "non-members cannot see a project's files or members" do
    project = make_project
    sign_in @outsider
    get project_files_path(project)
    assert_response :forbidden
    get project_memberships_path(project)
    assert_response :forbidden
  end

  test "a project manager can add users but not other project managers" do
    project = make_project
    sign_in @pm
    post project_memberships_path(project), params: { user_id: @outsider.id, role: "project_manager" }
    assert_response :forbidden
    post project_memberships_path(project), params: { user_id: @outsider.id, role: "supervisor" }
    assert_equal "supervisor", project.role_for(@outsider)
  end
end
