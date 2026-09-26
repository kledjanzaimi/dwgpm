require "test_helper"

class ActivityFlowTest < ActionDispatch::IntegrationTest
  setup do
    clear_storage!
    @admin = create_user("Admin", admin: true)
    @pm = create_user("Pam Manager")
    @sup = create_user("Sue Pervisor")
    @project = create_project("acme-123", creator: @admin)
    @other = create_project("other-9", creator: @admin)
    @project.memberships.create!(user: @pm, role: "project_manager")
    @project.memberships.create!(user: @sup, role: "supervisor")
    @other.memberships.create!(user: @sup, role: "project_manager")

    log = ->(project, action, path, **opts) {
      AuditLog.record!(user: opts[:user] || @sup, project: project, action: action, path: path,
                       ip: "10.0.0.7", detail: opts[:detail], allowed: opts.fetch(:allowed, true))
    }
    log.(@project, "upload", "01_Incoming/brief.pdf")
    log.(@project, "delete", "01_Incoming/old.dwg")
    log.(@project, "reject", "../../etc", allowed: false, detail: "path escapes project root")
    log.(@other, "upload", "01_Incoming/secret-other.pdf")
    log.(nil, "login", "", user: @pm)
  end

  test "a project manager sees their project's activity and nothing else" do
    sign_in @pm
    get project_activity_path(@project)
    assert_response :success
    assert_includes response.body, "01_Incoming/brief.pdf"
    assert_includes response.body, "Deleted"
    assert_not_includes response.body, "secret-other.pdf"
    assert_not_includes response.body, "Signed in"

    get project_activity_path(@other)
    assert_response :forbidden
    get activity_path
    assert_response :forbidden
  end

  test "supervisors and users cannot see a project's activity" do
    sign_in @sup
    get project_activity_path(@project)
    assert_response :forbidden
  end

  test "admin sees everything, including sign-ins" do
    sign_in @admin
    get activity_path
    assert_response :success
    %w[brief.pdf secret-other.pdf Signed\ in].each { |s| assert_includes response.body, s }
  end

  test "filters narrow the list" do
    sign_in @admin
    get activity_path, params: { denied: "1" }
    assert_includes response.body, "Blocked path"
    assert_not_includes response.body, "brief.pdf"

    get activity_path, params: { q: "old.dwg" }
    assert_includes response.body, "01_Incoming/old.dwg"
    assert_not_includes response.body, "brief.pdf"

    get activity_path, params: { project_id: @other.id }
    assert_includes response.body, "secret-other.pdf"
    assert_not_includes response.body, "brief.pdf"
  end

  test "pages older entries without repeating any" do
    60.times { |i| AuditLog.record!(user: @sup, project: @project, action: "download", path: "f#{i}.pdf", ip: nil) }
    sign_in @pm
    get project_activity_path(@project)
    assert_select "table.activity tbody tr", 50
    older = css_select("p.pager a").first["href"]

    get older
    assert_select "table.activity tbody tr", 13 # 60 downloads + 3 seeded, minus the first 50
    assert_select "p.pager", 0
  end
end
