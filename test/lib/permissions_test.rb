require "test_helper"

class PermissionsTest < ActiveSupport::TestCase
  setup do
    clear_storage!
    @admin = create_user("Admin", admin: true)
    @pm = create_user("Pam Manager")
    @sup = create_user("Sue Pervisor")
    @user = create_user("Uma User")
    @outsider = create_user("Oscar Outsider")
    @project = create_project("acme-123", creator: @admin)
    @project.memberships.create!(user: @pm, role: "project_manager")
    @project.memberships.create!(user: @sup, role: "supervisor")
    @project.memberships.create!(user: @user, role: "user")
  end

  def can?(user, action, path)
    Permissions.can?(user: user, project: @project, action: action, rel_path: path)
  end

  test "admin can do everything, everywhere" do
    assert can?(@admin, "delete", "00_Admin")
    assert can?(@admin, "upload", "99_Undefined")
  end

  test "non-members and nil users get nothing" do
    refute can?(@outsider, "view", "")
    refute can?(nil, "view", "")
  end

  test "any member may list the project root but not write to it" do
    assert can?(@user, "view", "")
    refute can?(@pm, "upload", "")
  end

  test "roles get exactly what the template grants" do
    refute can?(@user, "view", "00_Admin")
    assert can?(@sup, "view", "00_Admin")
    refute can?(@sup, "upload", "00_Admin")
    assert can?(@user, "upload", "01_Incoming/clientX")
    refute can?(@user, "delete", "01_Incoming")
    assert can?(@sup, "delete", "01_Incoming")
  end

  test "unknown actions are denied" do
    refute can?(@admin, "chmod", "01_Incoming")
  end

  test "only admins and project managers can assign roles" do
    assert_equal Membership::ROLES, Permissions.assignable_roles(user: @admin, project: @project)
    assert_equal %w[user supervisor], Permissions.assignable_roles(user: @pm, project: @project)
    assert_empty Permissions.assignable_roles(user: @sup, project: @project)
  end
end
