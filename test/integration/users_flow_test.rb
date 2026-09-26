require "test_helper"

class UsersFlowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("Admin", admin: true)
    @user = create_user("Uma User")
  end

  test "admin can disable and re-enable a user, and both are audited" do
    sign_in @admin
    delete user_path(@user)
    assert @user.reload.disabled_at

    get users_path
    assert_select "button.enable", "Enable"

    patch enable_user_path(@user)
    assert_nil @user.reload.disabled_at
    assert_equal %w[user_disable user_enable],
                 AuditLog.where(action: %w[user_disable user_enable]).order(:id).pluck(:action)

    post login_path, params: { email: @user.email, password: PASSWORD }
    assert_redirected_to root_path
  end

  test "only admins can enable users" do
    @user.update!(disabled_at: Time.current)
    other = create_user("Pam Manager")
    sign_in other
    patch enable_user_path(@user)
    assert_response :forbidden
    assert @user.reload.disabled_at
  end
end
